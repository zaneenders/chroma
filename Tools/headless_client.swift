#!/usr/bin/env swift
// Dependency-free JSONL demo client. Run: swift Tools/headless_client.swift [executable]
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct ProtocolError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

func check(_ condition: Bool, _ message: String = "assertion failed") throws {
  if !condition { throw ProtocolError(message) }
}

typealias Object = [String: Any]

final class HeadlessClient {
  let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let errors = Pipe()
  private let timeout: Double
  private var buffer = Data()
  private var diagnosticsData = Data()
  private var outputEOF = false
  private var errorsEOF = false
  private var inputClosed = false

  var diagnostics: String { String(decoding: diagnosticsData, as: UTF8.self) }

  init(_ executable: String, arguments: [String] = ["--headless"], timeout: Double,
       environment: [String: String]? = nil) throws {
    self.timeout = timeout
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    input.fileHandleForReading.closeFile()
    output.fileHandleForWriting.closeFile()
    errors.fileHandleForWriting.closeFile()
    for handle in [input.fileHandleForWriting, output.fileHandleForReading, errors.fileHandleForReading] {
      let fd = handle.fileDescriptor
      _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }
  }

  static func encode(_ request: Object) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys, .withoutEscapingSlashes])
    data.append(10)
    return data
  }

  // Drain both output pipes while writing bursts, so full pipes cannot deadlock each other.
  private func pump(until deadline: Date, writing: Bool = false) throws {
    try check(Date() < deadline, "pipe deadline exceeded; stderr: \(diagnostics)")
    var descriptors = [
      pollfd(fd: outputEOF ? -1 : output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
      pollfd(fd: errorsEOF ? -1 : errors.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
      pollfd(fd: writing ? input.fileHandleForWriting.fileDescriptor : -1, events: Int16(POLLOUT), revents: 0),
    ]
    let result = poll(&descriptors, nfds_t(descriptors.count), 20)
    if result < 0 && errno != EINTR { throw ProtocolError("poll failed: \(errno)") }
    for index in 0..<2 where descriptors[index].revents != 0 {
      var bytes = [UInt8](repeating: 0, count: 65536)
      let count = read(descriptors[index].fd, &bytes, bytes.count)
      if count > 0 {
        if index == 0 { buffer.append(contentsOf: bytes.prefix(count)) }
        else {
          diagnosticsData.append(contentsOf: bytes.prefix(count))
          diagnosticsData = Data(diagnosticsData.suffix(65536))
        }
      } else if count == 0 {
        if index == 0 { outputEOF = true } else { errorsEOF = true }
      } else if errno != EAGAIN && errno != EINTR {
        throw ProtocolError("pipe read failed: \(errno)")
      }
    }
  }

  func writeRaw(_ data: Data) throws {
    let deadline = Date().addingTimeInterval(timeout)
    var offset = 0
    while offset < data.count {
      try pump(until: deadline, writing: true)
      let count = data.withUnsafeBytes {
        write(input.fileHandleForWriting.fileDescriptor, $0.baseAddress!.advanced(by: offset), data.count - offset)
      }
      if count > 0 { offset += count }
      else if count == 0 || (errno != EAGAIN && errno != EINTR) {
        throw ProtocolError("stdin write failed: \(errno); stderr: \(diagnostics)")
      }
    }
  }

  func send(_ request: Object) throws { try writeRaw(Self.encode(request)) }
  func sendMany(_ requests: [Object]) throws {
    try writeRaw(requests.reduce(into: Data()) { $0.append(try Self.encode($1)) })
  }
  private func nextLine() throws -> Data? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      if let newline = buffer.firstIndex(of: 10) {
        let line = Data(buffer.prefix(through: newline))
        buffer.removeSubrange(...newline)
        return line
      }
      if outputEOF {
        try check(buffer.isEmpty, "response lacks a newline")
        return nil
      }
      try pump(until: deadline)
    }
  }
  func receive() throws -> Object {
    guard let line = try nextLine() else { throw ProtocolError("unexpected stdout EOF; stderr: \(diagnostics)") }
    try check(String(data: line, encoding: .utf8) != nil, "response is not UTF-8")
    guard let object = try JSONSerialization.jsonObject(with: line) as? Object else {
      throw ProtocolError("response is not a JSON object")
    }
    try check(JSONSerialization.isValidJSONObject(object), "response contains nonfinite numbers")
    return object
  }
  func request(_ op: String, _ fields: Object = [:]) throws -> Object {
    var request = fields
    request["version"] = 1
    request["op"] = op
    try send(request)
    return try receive()
  }
  func closeInput() {
    if !inputClosed { input.fileHandleForWriting.closeFile(); inputClosed = true }
  }
  func expectEOF() throws -> Int32 {
    try check(try nextLine() == nil, "unexpected extra stdout line")
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning || !errorsEOF { try pump(until: deadline) }
    return process.terminationStatus
  }
  func close() {
    closeInput()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      do { try pump(until: deadline) } catch { break }
    }
    if process.isRunning {
      process.terminate()
      let grace = Date().addingTimeInterval(2)
      while process.isRunning && Date() < grace { usleep(10000) }
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()
    output.fileHandleForReading.closeFile()
    errors.fileHandleForReading.closeFile()
  }
}

func main() throws {
  var executable = ".build/debug/ChromaHeadlessDemo"
  var viewport = "800x600"
  var text = "Hello from a subprocess"
  var positionalSeen = false
  var arguments = Array(CommandLine.arguments.dropFirst())
  while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--help", "-h":
      print("Usage: swift Tools/headless_client.swift [executable] [--viewport WIDTHxHEIGHT] [--text TEXT]")
      return
    case "--viewport", "--text":
      guard !arguments.isEmpty else { throw ProtocolError("\(argument) requires a value") }
      let value = arguments.removeFirst()
      if argument == "--viewport" { viewport = value } else { text = value }
    default:
      guard !argument.hasPrefix("-"), !positionalSeen else {
        throw ProtocolError("unexpected argument: \(argument)")
      }
      executable = argument
      positionalSeen = true
    }
  }
  _ = signal(SIGPIPE, SIG_IGN)
  let client = try HeadlessClient(executable, arguments: ["--headless", "--viewport", viewport], timeout: 10)
  defer { client.close() }
  let requests: [Object] = [
    ["version": 1, "id": "initial", "op": "frame"],
    ["version": 1, "id": "focus", "op": "key", "key": "tab"],
    ["version": 1, "id": "edit", "op": "key", "key": "enter"],
    ["version": 1, "id": "type", "op": "key", "text": text],
    ["version": 1, "id": "final", "op": "frame"],
    ["version": 1, "id": "quit", "op": "quit"],
  ]
  try client.sendMany(requests)
  for request in requests {
    let response = try client.receive()
    try check(response["id"] as? String == request["id"] as? String, "out-of-order response: \(response)")
    let expected = request["op"] as? String == "quit" ? "closed" : "frame"
    try check(response["status"] as? String == expected, "unexpected response: \(response)")
    FileHandle.standardOutput.write(try HeadlessClient.encode(response))
  }
  try check(client.expectEOF() == 0, "process exited unsuccessfully: \(client.diagnostics)")
  if !client.diagnostics.isEmpty {
    FileHandle.standardError.write(Data(client.diagnostics.utf8))
  }
}

do { try main() }
catch {
  FileHandle.standardError.write(Data("headless client: \(error)\n".utf8))
  exit(1)
}
