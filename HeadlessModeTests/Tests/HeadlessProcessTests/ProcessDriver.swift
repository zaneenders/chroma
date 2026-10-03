import Foundation
import Subprocess
import Testing

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct WireRequest: Codable, Sendable {
  enum Operation: String, Codable, Sendable {
    case key, frame, quit, resize, pointer
  }

  var version = 1
  var id: String? = nil
  let op: Operation
  var key: String? = nil
  var text: String? = nil
  var width: Double? = nil
  var height: Double? = nil
  var phase: String? = nil
  var x: Double? = nil
  var y: Double? = nil

  func encoded(terminated: Bool = true) throws -> Data {
    var data = try JSONEncoder().encode(self)
    if terminated { data.append(10) }
    return data
  }
}

struct WireResponse: Decodable, Sendable {
  struct Viewport: Decodable, Sendable, Equatable {
    let width: Double
    let height: Double
  }
  struct Point: Decodable, Sendable {
    let x: Double
    let y: Double
  }
  struct Text: Decodable, Sendable {
    let text: String
    let position: Point
  }
  struct Command: Decodable, Sendable { let text: Text? }
  struct Focus: Decodable, Sendable {
    let editing: Bool
    let path: [Int]?
    let caretOffset: Int?
  }

  let version: Int
  let id: String?
  let status: String
  let error: String?
  let viewport: Viewport?
  let commands: [Command]?
  let focus: Focus?

  var texts: [String] { (commands ?? []).compactMap { $0.text?.text } }

  func requireFrame(id expectedID: String) throws {
    try #require(version == 1)
    try #require(id == expectedID)
    try #require(status == "frame")
    try #require(error == nil)
    try #require(viewport != nil)
    try #require(commands != nil)
  }
}

struct DriverFailure: Error, CustomStringConvertible {
  let description: String
}

struct DeadlineExceeded: Error, CustomStringConvertible {
  let description: String
}

/// Unlike a timeout around a blocking read, cancellation wakes this mailbox's
/// suspended consumer, allowing the Subprocess closure to unwind and reap its child.
actor Responses {
  private var queued: [WireResponse] = []
  private var waiter: (UUID, CheckedContinuation<WireResponse, any Error>)?
  private var ended = false
  private var failure: (any Error)?

  func append(_ response: WireResponse) {
    if let (_, continuation) = waiter {
      waiter = nil
      continuation.resume(returning: response)
    } else {
      queued.append(response)
    }
  }

  func finish(throwing error: (any Error)? = nil) {
    ended = true
    failure = error
    if let (_, continuation) = waiter {
      waiter = nil
      continuation.resume(throwing: error ?? DriverFailure(description: "Unexpected stdout EOF"))
    }
  }

  func next() async throws -> WireResponse {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        if !queued.isEmpty {
          continuation.resume(returning: queued.removeFirst())
        } else if ended {
          continuation.resume(throwing: failure ?? DriverFailure(description: "Unexpected stdout EOF"))
        } else {
          precondition(waiter == nil, "Only one response consumer is supported")
          waiter = (id, continuation)
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  private func cancel(_ id: UUID) {
    guard let (waitingID, continuation) = waiter, waitingID == id else { return }
    waiter = nil
    continuation.resume(throwing: CancellationError())
  }

  func requireDrained() throws {
    try #require(ended, "stdout must reach EOF")
    try #require(queued.isEmpty, "Unsolicited or unconsumed protocol responses")
  }
}

actor Diagnostics {
  private var data = Data()
  var text: String { String(decoding: data, as: UTF8.self) }
  private var waiters: [UUID: (String, CheckedContinuation<Void, any Error>)] = [:]
  private var ended = false

  func append(_ chunk: Data) {
    data.append(chunk)
    guard !waiters.isEmpty else { return }
    let currentText = text
    for (id, (marker, continuation)) in waiters where currentText.contains(marker) {
      waiters.removeValue(forKey: id)
      continuation.resume()
    }
  }

  func finish() {
    ended = true
    let pending = waiters
    waiters.removeAll()
    for (_, (_, continuation)) in pending {
      continuation.resume(throwing: DriverFailure(description: "stderr ended before expected diagnostic"))
    }
  }

  func wait(for marker: String) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        if text.contains(marker) {
          continuation.resume()
        } else if ended {
          continuation.resume(throwing: DriverFailure(description: "Missing diagnostic: \(marker)"))
        } else {
          waiters[id] = (marker, continuation)
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  private func cancel(_ id: UUID) {
    waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
  }
}

func withDeadline<T: Sendable>(
  _ label: String, after duration: Duration = .seconds(10),
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask(operation: operation)
    group.addTask {
      try await Task.sleep(for: duration)
      throw DeadlineExceeded(description: "Deadline exceeded: \(label)")
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}

/// Decode each stdout line separately. A log line on stdout is a decoding error,
/// rather than being silently skipped or confused with stderr diagnostics.
private func decodeJSONL(_ output: SubprocessOutputSequence, into responses: Responses) async throws {
  do {
    for try await line in output.strings(separatedBy: .unicodeScalarSequence("\n".unicodeScalars)) {
      let response = try JSONDecoder().decode(WireResponse.self, from: Data(line.utf8))
      await responses.append(response)
    }
    await responses.finish()
  } catch {
    await responses.finish(throwing: error)
    throw error
  }
}

struct ProcessClient: Sendable {
  // These values are used only in structured tasks inside Subprocess.run's body.
  let input: StandardInputWriter
  let responses: Responses
  let diagnostics: Diagnostics
  let pid: pid_t

  func sendRaw(_ data: Data) async throws { _ = try await input.write(data) }

  func send(_ request: WireRequest, terminated: Bool = true) async throws {
    try await sendRaw(request.encoded(terminated: terminated))
  }

  func send(_ requests: [WireRequest]) async throws {
    var data = Data()
    for request in requests { data.append(try request.encoded()) }
    try await sendRaw(data)
  }

  func receive() async throws -> WireResponse { try await responses.next() }

  func request(_ request: WireRequest) async throws -> WireResponse {
    try await send(request)
    return try await receive()
  }
}

struct ProcessOutcome: Sendable {
  let status: TerminationStatus
  let diagnostics: String

  func requireSuccess() throws {
    try #require(status == .exited(0), "Child exited \(status); stderr: \(diagnostics)")
  }
}

func executable(_ variable: String) throws -> Executable {
  let path = try #require(
    ProcessInfo.processInfo.environment[variable],
    "Set CHROMA_HEADLESS_DEMO and CHROMA_HEADLESS_FIXTURE to the built executables; see HeadlessModeTests/README.md")
  try #require(FileManager.default.isExecutableFile(atPath: path), "Missing executable: \(path)")
  return .path(.init(path))
}

func runSession(
  _ variable: String = "CHROMA_HEADLESS_DEMO",
  arguments: Arguments = ["--headless"],
  environment: Environment = .inherit,
  body: @escaping @Sendable (ProcessClient) async throws -> Void
) async throws -> ProcessOutcome {
  let program = try executable(variable)
  let responses = Responses()
  let diagnostics = Diagnostics()
  return try await withDeadline("\(variable) session") {
    let result = try await Subprocess.run(
      program, arguments: arguments, environment: environment,
      input: .inputWriter, output: .sequence, error: .sequence
    ) { execution in
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await decodeJSONL(execution.standardOutput, into: responses) }
        group.addTask {
          // Diagnostics need not contain newlines. Drain byte chunks without a
          // line limit, preserving UTF-8 even when scalars cross read boundaries.
          for try await chunk in execution.standardError {
            await diagnostics.append(chunk.withUnsafeBytes { Data($0) })
          }
          await diagnostics.finish()
        }
        group.addTask {
          try await body(
            ProcessClient(
              input: execution.standardInputWriter,
              responses: responses, diagnostics: diagnostics,
              pid: execution.processIdentifier.value))
          try await execution.standardInputWriter.finish()
        }
        // Observe failures immediately so a failed driver cancels pipe readers;
        // waitForAll() would keep waiting for their EOF while stdin stays open.
        while try await group.next() != nil {}
      }
    }
    try await responses.requireDrained()
    return ProcessOutcome(status: result.terminationStatus, diagnostics: await diagnostics.text)
  }
}

actor DeadlineProbe {
  private(set) var pid: pid_t?
  private(set) var startedAt: ContinuousClock.Instant?
  func begin(_ processID: pid_t) {
    pid = processID
    startedAt = .now
  }
}

func requireReaped(_ pid: pid_t) throws {
  // A zombie still answers kill(pid, 0), so ESRCH proves the run has reaped it.
  let result = kill(pid, 0)
  let error = errno
  try #require(result == -1 && error == ESRCH, "Child \(pid) survived cleanup (kill=\(result), errno=\(error))")
}
