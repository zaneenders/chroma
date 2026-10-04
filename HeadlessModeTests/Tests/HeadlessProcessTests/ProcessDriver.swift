import Chroma
import ChromaFont
import ChromaHeadless
import Foundation
import Subprocess
import Testing

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension HeadlessRequest {
  func encoded(terminated: Bool = true) throws -> Data {
    var data = try JSONEncoder().encode(self)
    if terminated { data.append(10) }
    return data
  }
}

extension HeadlessResponse {
  var textRuns: [(position: Chroma.Point, text: String)] {
    let atlas = HighResolutionFontAtlas()
    var result: [(position: Chroma.Point, text: String)] = []
    var lastQuad: Chroma.DrawQuad?
    for entry in commands ?? [] {
      guard case .quad(let quad) = entry, quad.texture == .fontAtlas else {
        lastQuad = nil
        continue
      }
      var character = "�"
      for scalar in atlas.characterIndices.keys {
        let candidate = Character(String(UnicodeScalar(scalar)!))
        let (x, y, _, _) = atlas.glyphUV(candidate)
        if x == quad.sourceRect.minX && y == quad.sourceRect.minY {
          character = String(candidate)
          break
        }
      }
      if let previous = lastQuad, previous.colors == quad.colors,
        previous.rect.minY == quad.rect.minY,
        abs(previous.rect.minX + previous.rect.size.width * 0.6 - quad.rect.minX) < 0.001
      {
        result[result.count - 1].text += character
      } else {
        result.append((quad.rect.origin, character))
      }
      lastQuad = quad
    }
    return result
  }

  var texts: [String] { textRuns.map(\.text) }

  func requireFrame(id expectedID: UUID) throws {
    try requireFrame(id: expectedID.uuidString)
  }

  func requireFrame(id expectedID: String) throws {
    try #require(version == 1)
    try #require(id == expectedID)
    try #require(status == .frame)
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
  private var queued: [HeadlessResponse] = []
  private var waiter: (UUID, CheckedContinuation<HeadlessResponse, any Error>)?
  private var ended = false
  private var failure: (any Error)?

  func append(_ response: HeadlessResponse) {
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

  func next() async throws -> HeadlessResponse {
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

  func waitForEOF() async throws {
    while !ended {
      try await Task.sleep(for: .milliseconds(10))
    }
    if let failure { throw failure }
  }

  func requireDrained() throws {
    try #require(ended, "stdout must reach EOF")
    try #require(queued.isEmpty, "Unsolicited or unconsumed protocol responses")
  }
}

actor Diagnostics {
  private var data = Data()
  var text: String { String(decoding: data, as: UTF8.self) }
  func append(_ chunk: Data) { data.append(chunk) }
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
private func decodeJSONL(_ output: SubprocessOutputSequence, into responses: Responses, frames: Responses) async throws
{
  do {
    for try await line in output.strings(separatedBy: .unicodeScalarSequence("\n".unicodeScalars)) {
      let response = try JSONDecoder().decode(HeadlessResponse.self, from: Data(line.utf8))
      if response.status == .frame && response.id == nil {
        await frames.append(response)
      } else {
        await responses.append(response)
      }
    }
    await frames.finish()
    await responses.finish()
  } catch {
    await frames.finish(throwing: error)
    await responses.finish(throwing: error)
    throw error
  }
}

struct ProcessClient: Sendable {
  // These values are used only in structured tasks inside Subprocess.run's body.
  let input: StandardInputWriter
  let responses: Responses
  let frames: Responses
  let diagnostics: Diagnostics
  let pid: pid_t

  func sendRaw(_ data: Data) async throws { _ = try await input.write(data) }

  func send(_ request: HeadlessRequest, terminated: Bool = true) async throws {
    try await sendRaw(request.encoded(terminated: terminated))
  }

  func send(_ requests: [HeadlessRequest]) async throws {
    var data = Data()
    for request in requests { data.append(try request.encoded()) }
    try await sendRaw(data)
  }

  func receive() async throws -> HeadlessResponse { try await responses.next() }

  func waitForText(_ text: String) async throws -> HeadlessResponse {
    try await withDeadline("stdout text: \(text)") {
      while true {
        let frame = try await frames.next()
        if frame.texts.contains(text) { return frame }
      }
    }
  }

  func request(_ request: HeadlessRequest) async throws -> HeadlessResponse {
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

private final class TestBundleMarker: NSObject {}

func executable(_ name: String) throws -> Executable {
  // SwiftPM places executables beside the test binary (or its macOS .xctest bundle).
  #if canImport(Darwin)
  var directory = Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent()
  #else
  var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
  #endif
  while true {
    let path = directory.appendingPathComponent(name).path
    if FileManager.default.isExecutableFile(atPath: path) { return .path(.init(path)) }
    let parent = directory.deletingLastPathComponent()
    guard parent.path != directory.path else { break }
    directory = parent
  }
  throw DriverFailure(description: "Missing built executable: \(name); run swift test in HeadlessModeTests")
}

func runSession(
  _ name: String = "ChromaHeadlessDemo",
  arguments: Arguments = ["--viewport", "800x600"],
  environment: Environment = .inherit,
  body: @escaping @Sendable (ProcessClient) async throws -> Void
) async throws -> ProcessOutcome {
  let program = try executable(name)
  let responses = Responses()
  let frames = Responses()
  let diagnostics = Diagnostics()
  return try await withDeadline("\(name) session") {
    let result = try await Subprocess.run(
      program, arguments: arguments, environment: environment,
      input: .inputWriter, output: .sequence, error: .sequence
    ) { execution in
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await decodeJSONL(execution.standardOutput, into: responses, frames: frames) }
        group.addTask {
          // Diagnostics need not contain newlines. Drain byte chunks without a
          // line limit, preserving UTF-8 even when scalars cross read boundaries.
          for try await chunk in execution.standardError {
            await diagnostics.append(chunk.withUnsafeBytes { Data($0) })
          }
        }
        group.addTask {
          try await body(
            ProcessClient(
              input: execution.standardInputWriter,
              responses: responses, frames: frames, diagnostics: diagnostics,
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
