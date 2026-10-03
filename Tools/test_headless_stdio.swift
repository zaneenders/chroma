#!/usr/bin/env swift
// Real-pipe integration tests: swift Tools/test_headless_stdio.swift [executable] [--timeout seconds]
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct TestFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

func check(_ condition: Bool, _ message: String = "assertion failed") throws {
  if !condition { throw TestFailure(message) }
}

func equal(_ actual: Any?, _ expected: Any, file: String = #filePath, line: Int = #line) throws {
  let matches = actual.map { NSDictionary(dictionary: ["value": $0]).isEqual(to: ["value": expected]) } ?? false
  try check(matches, "\(file):\(line): expected \(expected), got \(String(describing: actual))")
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
    if result < 0 && errno != EINTR { throw TestFailure("poll failed: \(errno)") }
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
        throw TestFailure("pipe read failed: \(errno)")
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
        throw TestFailure("stdin write failed: \(errno); stderr: \(diagnostics)")
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
    guard let line = try nextLine() else { throw TestFailure("unexpected stdout EOF; stderr: \(diagnostics)") }
    try check(String(data: line, encoding: .utf8) != nil, "response is not UTF-8")
    guard let object = try JSONSerialization.jsonObject(with: line) as? Object else {
      throw TestFailure("response is not a JSON object")
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

func frameTexts(_ frame: Object) -> [String] {
  (frame["commands"] as? [Object] ?? []).compactMap { ($0["text"] as? Object)?["text"] as? String }
}
func assertFrame(_ response: Object, _ id: String? = nil) throws {
  try equal(response["version"], 1)
  try equal(response["status"], "frame")
  try check(response["commands"] is [Object] && response["viewport"] is Object && response["error"] == nil)
  try check(JSONSerialization.isValidJSONObject(response), "nonfinite response")
  if let id { try equal(response["id"], id) }
}
func assertError(_ response: Object) throws {
  try equal(response["version"], 1)
  try equal(response["status"], "error")
  try check(!(response["error"] as? String ?? "").isEmpty)
}
func assertClosed(_ client: HeadlessClient) throws {
  let response = try client.request("quit", ["id": "quit"])
  try equal(response["version"], 1)
  try equal(response["id"], "quit")
  try equal(response["status"], "closed")
  try equal(client.expectEOF(), Int32(0))
}
func textPosition(_ frame: Object, _ text: String) throws -> Object {
  for command in frame["commands"] as? [Object] ?? [] {
    if let draw = command["text"] as? Object, draw["text"] as? String == text,
       let position = draw["position"] as? Object { return position }
  }
  throw TestFailure("missing text: \(text)")
}
func click(_ client: HeadlessClient, _ position: Object) throws -> Object {
  guard let x = position["x"] as? Double, let y = position["y"] as? Double else {
    throw TestFailure("invalid text position")
  }
  var response: Object = [:]
  for phase in ["move", "down", "up"] {
    response = try client.request("pointer", ["phase": phase, "x": x + 2, "y": y + 2])
    try assertFrame(response)
  }
  return response
}

struct Suite {
  let executable: String
  let timeout: Double
  func withClient(_ arguments: [String] = ["--headless"], environment: [String: String]? = nil,
                  _ body: (HeadlessClient) throws -> Void) throws {
    let client = try HeadlessClient(executable, arguments: arguments, timeout: timeout, environment: environment)
    defer { client.close() }
    try body(client)
  }
  func burst(_ client: HeadlessClient, _ operations: [(String, Object)]) throws -> [Object] {
    try client.sendMany(operations.enumerated().map { ["version": 1, "id": String($0.offset), "op": $0.element.0].merging($0.element.1) { _, new in new } })
    return try operations.indices.map { index in
      let response = try client.receive()
      try assertFrame(response, String(index))
      return response
    }
  }
  func tests() -> [(String, () throws -> Void)] {
    [
      ("explicit_frames_are_deterministic_and_default_viewport", { try withClient { client in
        let first = try client.request("frame", ["id": "first"])
        try assertFrame(first, "first")
        try check(!(first["commands"] as! [Object]).isEmpty)
        try equal(first["viewport"], ["width": 800, "height": 600])
        let second = try client.request("frame", ["id": "second"])
        try assertFrame(second, "second")
        try equal(first["commands"], second["commands"]!)
        for text in ["First", "Second", "Count: 0"] { try check(frameTexts(first).contains(text)) }
        try assertClosed(client)
      }}),
      ("burst_text_tab_text_preserves_order_and_target", { try withClient { client in
        let responses = try burst(client, [("frame", [:]), ("key", ["key": "tab"]), ("key", ["key": "enter"]), ("key", ["text": "Alpha"]), ("key", ["key": "tab"]), ("key", ["key": "enter"]), ("key", ["text": "Beta"]), ("frame", [:])])
        let last = responses.last!
        try check(frameTexts(responses[3]).contains("Alpha"))
        try check(frameTexts(last).contains("Alpha") && frameTexts(last).contains("Beta") && !frameTexts(last).contains("AlphaBeta"))
        let firstFocus = responses[3]["focus"] as! Object
        let lastFocus = last["focus"] as! Object
        try equal(firstFocus["editing"], true); try equal(firstFocus["caretOffset"], 5)
        try equal(lastFocus["editing"], true); try equal(lastFocus["caretOffset"], 4)
        try check(!NSDictionary(dictionary: firstFocus).isEqual(to: lastFocus))
        try check(!NSDictionary(dictionary: ["path": firstFocus["path"]!]).isEqual(to: ["path": lastFocus["path"]!]))
        try assertClosed(client)
      }}),
      ("repeated_keys_are_not_coalesced", { try withClient { client in
        let operations: [(String, Object)] = [("key", ["key": "tab"]), ("key", ["key": "enter"])] + Array(repeating: ("key", ["key": "a", "text": "a"]), count: 12) + Array(repeating: ("key", ["key": "backspace"]), count: 5) + [("key", ["text": "Z"])]
        let responses = try burst(client, operations)
        try check(frameTexts(responses[13]).contains(String(repeating: "a", count: 12)))
        try check(frameTexts(responses.last!).contains(String(repeating: "a", count: 7) + "Z"))
        try assertClosed(client)
      }}),
      ("pointer_edits_distinct_controls_and_activates_button", { try withClient { client in
        let initial = try client.request("frame")
        try assertFrame(initial)
        let first = try textPosition(initial, "First"), second = try textPosition(initial, "Second"), button = try textPosition(initial, "Count: 0")
        _ = try click(client, first)
        try check(frameTexts(client.request("key", ["text": "Pointer one"])).contains("Pointer one"))
        _ = try click(client, second)
        let typed = try client.request("key", ["text": "Pointer two"])
        try check(frameTexts(typed).contains("Pointer one") && frameTexts(typed).contains("Pointer two"))
        try check(frameTexts(click(client, button)).contains("Count: 1"))
        try check(frameTexts(click(client, button)).contains("Count: 2"))
        try assertClosed(client)
      }}),
      ("resize_scroll_and_initial_cli_viewport", { try withClient(["--headless", "--viewport", "640x480"]) { client in
        let initial = try client.request("frame")
        try assertFrame(initial); try equal(initial["viewport"], ["width": 640, "height": 480])
        for (width, height) in [(1024, 768), (1, 1), (16384, 16384), (800, 600)] {
          let response = try client.request("resize", ["width": width, "height": height])
          try assertFrame(response); try equal(response["viewport"], ["width": width, "height": height])
        }
        try assertFrame(client.request("scroll", ["x": 0, "y": -24]))
        try assertFrame(client.request("scroll", ["x": 12, "y": 0]))
        try assertClosed(client)
      }}),
      ("invalid_requests_recover_without_changing_viewport", { try withClient { client in
        let invalid: [Object] = [
          ["version": 2, "op": "frame"], ["op": "frame"], ["version": "1", "op": "frame"], ["version": 1, "op": "unknown"],
          ["version": 1, "op": "resize", "width": 0, "height": 600], ["version": 1, "op": "resize", "width": -1, "height": 600],
          ["version": 1, "op": "resize", "width": 16385, "height": 600], ["version": 1, "op": "resize", "width": 800, "height": 16385],
          ["version": 1, "op": "resize", "width": "800", "height": 600], ["version": 1, "op": "resize", "width": 800],
          ["version": 1, "op": "pointer", "phase": "down", "x": 1000001, "y": 0], ["version": 1, "op": "pointer", "phase": "down", "x": 0, "y": -1000001],
          ["version": 1, "op": "pointer", "phase": "bogus", "x": 0, "y": 0], ["version": 1, "op": "pointer", "phase": "move", "x": 0],
          ["version": 1, "op": "scroll", "x": 0, "y": 1000001], ["version": 1, "op": "key", "key": "not-a-key"],
          ["version": 1, "op": "key", "key": "a", "modifiers": ["unknown"]],
          ["version": 1, "op": "key", "text": String(repeating: "x", count: 16385)], ["version": 1, "op": "key", "text": String(repeating: "é", count: 8193)],
          ["version": 1, "op": "frame", "id": String(repeating: "i", count: 257)], ["version": 1, "op": "frame", "id": String(repeating: "é", count: 129)],
        ]
        for (index, request) in invalid.enumerated() {
          try client.send(request); try assertError(client.receive())
          let recovered = try client.request("frame", ["id": "recover-\(index)"])
          try assertFrame(recovered, "recover-\(index)"); try equal(recovered["viewport"], ["width": 800, "height": 600])
        }
        try assertClosed(client); try check(!client.diagnostics.isEmpty, "protocol diagnostics must use stderr")
      }}),
      ("malformed_nonfinite_and_invalid_utf8_recover", { try withClient { client in
        let malformed = [Data("not json\n".utf8), Data("{\n".utf8), Data("[]\n".utf8), Data("null\n".utf8), Data([255, 10])] + [
          "{\"version\":1,\"op\":\"resize\",\"width\":1e999,\"height\":600}\n",
          "{\"version\":1,\"op\":\"resize\",\"width\":NaN,\"height\":600}\n",
          "{\"version\":1,\"op\":\"pointer\",\"phase\":\"down\",\"x\":Infinity,\"y\":0}\n",
          "{\"version\":1,\"op\":\"scroll\",\"x\":0,\"y\":-Infinity}\n",
        ].map { Data($0.utf8) }
        for (index, line) in malformed.enumerated() {
          try client.writeRaw(line + HeadlessClient.encode(["version": 1, "id": "valid-\(index)", "op": "frame"]))
          try assertError(client.receive()); try assertFrame(client.receive(), "valid-\(index)")
        }
        try assertClosed(client)
      }}),
      ("oversized_line_is_drained_once_and_next_request_recovers", { try withClient { client in
        try client.writeRaw(Data(repeating: 120, count: 200000) + Data([10]) + HeadlessClient.encode(["version": 1, "id": "after-large-line", "op": "frame"]))
        try assertError(client.receive()); try assertFrame(client.receive(), "after-large-line"); try assertClosed(client)
      }}),
      ("line_size_boundary_and_crlf", { try withClient { client in
        let base = Data("{\"version\":1,\"id\":\"boundary\",\"op\":\"frame\"}".utf8)
        try client.writeRaw(base + Data(repeating: 32, count: 65536 - base.count) + Data([10]))
        try assertFrame(client.receive(), "boundary")
        try client.writeRaw(base + Data(repeating: 32, count: 65537 - base.count) + Data([10]))
        try assertError(client.receive())
        try client.writeRaw(Data("{\"version\":1,\"id\":\"crlf\",\"op\":\"frame\"}\r\n".utf8))
        try assertFrame(client.receive(), "crlf"); try assertClosed(client)
      }}),
      ("valid_utf8_byte_limits_and_character_selection", { try withClient { client in
        let id = String(repeating: "é", count: 128)
        try assertFrame(client.request("frame", ["id": id]), id)
        _ = try client.request("key", ["key": "tab"]); _ = try client.request("key", ["key": "enter"])
        let text = "A👩‍💻e\u{0301}"
        let response = try client.request("key", ["text": text])
        try assertFrame(response); try check(frameTexts(response).contains(text))
        try equal((response["focus"] as? Object)?["caretOffset"], 3)
        let selected = try client.request("key", ["key": "left", "modifiers": ["shift"]])
        try assertFrame(selected)
        try equal((selected["focus"] as? Object)?["selectionStart"], 2)
        try equal((selected["focus"] as? Object)?["selectionEnd"], 3)
        try assertFrame(client.request("key", ["text": String(repeating: "é", count: 8192)])); try assertClosed(client)
      }}),
      ("invalid_pointer_transition_preserves_held_state", { try withClient { client in
        let point = try textPosition(client.request("frame"), "Count: 0")
        func pointer(_ phase: String) throws -> Object { try client.request("pointer", point.merging(["phase": phase]) { _, new in new }) }
        try assertError(pointer("up")); try assertFrame(pointer("down")); try assertError(pointer("down"))
        let released = try pointer("up")
        try assertFrame(released); try check(frameTexts(released).contains("Count: 1")); try assertClosed(client)
      }}),
      ("eof_without_requests_exits_without_unsolicited_stdout", { try withClient { client in
        client.closeInput(); try equal(client.expectEOF(), Int32(0))
      }}),
      ("eof_accepts_final_request_without_newline", { try withClient { client in
        try client.writeRaw(Data("{\"version\":1,\"id\":\"last\",\"op\":\"frame\"}".utf8))
        client.closeInput(); try assertFrame(client.receive(), "last"); try equal(client.expectEOF(), Int32(0))
      }}),
      ("eof_reports_partial_malformed_request_then_exits", { try withClient { client in
        try client.writeRaw(Data("{\"version\":1,\"op\":".utf8))
        client.closeInput(); try assertError(client.receive()); try equal(client.expectEOF(), Int32(0))
      }}),
      ("eof_drains_oversized_unterminated_request", { try withClient { client in
        try client.writeRaw(Data(repeating: 120, count: 100000))
        client.closeInput(); try assertError(client.receive()); try equal(client.expectEOF(), Int32(0))
      }}),
      ("quit_ignores_later_buffered_requests", { try withClient { client in
        try client.sendMany([["version": 1, "id": "quit", "op": "quit"], ["version": 1, "id": "ignored", "op": "frame"]])
        let response = try client.receive()
        try equal(response["status"], "closed"); try equal(response["id"], "quit"); try equal(client.expectEOF(), Int32(0))
      }}),
      ("executable_defaults_to_headless_without_flag", { try withClient([]) { client in
        try assertFrame(client.request("frame")); try assertClosed(client)
      }}),
      ("invalid_cli_arguments_exit_nonzero_on_stderr_only", {
        for arguments in [["--bogus"], ["--viewport"], ["--viewport", "800"], ["--viewport", "0x600"], ["--viewport", "-1x600"], ["--viewport", "16385x600"], ["--viewport", "NaNx600"], ["--viewport", "800xInfinity"]] {
          try withClient(arguments) { client in
            client.closeInput(); try check(client.expectEOF() != 0); try check(!client.diagnostics.isEmpty)
          }
        }
      }),
      ("no_display_environment_is_required", {
        var environment = ProcessInfo.processInfo.environment
        for variable in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"] { environment.removeValue(forKey: variable) }
        try withClient(environment: environment) { client in
          try client.send(["version": 1, "op": "frame"]); client.closeInput()
          try assertFrame(client.receive()); try equal(client.expectEOF(), Int32(0))
        }
      }),
    ]
  }
}

func main() throws {
  var executable = ".build/debug/ChromaHeadlessDemo"
  var timeout = 10.0
  var positionalSeen = false
  var arguments = Array(CommandLine.arguments.dropFirst())
  while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    if argument == "--help" || argument == "-h" {
      print("Usage: swift Tools/test_headless_stdio.swift [executable] [--timeout seconds]")
      return
    } else if argument == "--timeout" {
      guard !arguments.isEmpty, let value = Double(arguments.removeFirst()), value.isFinite, value > 0 else {
        throw TestFailure("--timeout requires a positive finite number")
      }
      timeout = value
    } else if !argument.hasPrefix("-"), !positionalSeen {
      executable = argument; positionalSeen = true
    } else { throw TestFailure("unexpected argument: \(argument)") }
  }
  executable = URL(fileURLWithPath: executable).standardizedFileURL.path
  try check(FileManager.default.isExecutableFile(atPath: executable), "executable not found: \(executable); build ChromaHeadlessDemo first")
  _ = signal(SIGPIPE, SIG_IGN)
  let tests = Suite(executable: executable, timeout: timeout).tests()
  var failures = 0
  for (name, test) in tests {
    do { try test(); print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name): \(error)") }
  }
  print("\(tests.count) tests, \(failures) failures")
  if failures > 0 { exit(1) }
}

do { try main() }
catch {
  FileHandle.standardError.write(Data("headless stdio tests: \(error)\n".utf8))
  exit(1)
}
