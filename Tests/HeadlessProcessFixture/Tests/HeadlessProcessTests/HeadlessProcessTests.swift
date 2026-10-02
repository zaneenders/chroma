import Foundation
import Subprocess
import Testing

struct HeadlessProcessTests {
  @Test func interactiveHandshakesThenOrderedTextTabTextBurst() async throws {
    let outcome = try await runSession { client in
      // Each write happens only after the previous response arrives, while stdin
      // remains open. This cannot pass with a pre-collected one-shot input string.
      // Unicode line separators in JSON strings are data, never JSONL delimiters.
      for id in ["hello", "still-alive\u{2028}\u{2029}\u{85}", "ready"] {
        let frame = try await client.request("{\"version\":1,\"id\":\"\(id)\",\"op\":\"frame\"}")
        try frame.requireFrame(id: id)
        #expect(frame.viewport == .init(width: 800, height: 600))
        #expect(frame.texts.contains("First"))
        #expect(frame.texts.contains("Second"))
      }

      // One write deliberately sends requests faster than frames can be rendered.
      let burst = [
        #"{"version":1,"id":"focus-first","op":"key","key":"tab"}"#,
        #"{"version":1,"id":"edit-first","op":"key","key":"enter"}"#,
        #"{"version":1,"id":"text-first","op":"key","text":"Alpha"}"#,
        #"{"version":1,"id":"focus-second","op":"key","key":"tab"}"#,
        #"{"version":1,"id":"edit-second","op":"key","key":"enter"}"#,
        #"{"version":1,"id":"text-second","op":"key","text":"Beta"}"#,
        #"{"version":1,"id":"snapshot","op":"frame"}"#,
      ]
      try await client.send(burst.joined(separator: "\n"))
      var received: [WireResponse] = []
      for id in ["focus-first", "edit-first", "text-first", "focus-second", "edit-second", "text-second", "snapshot"] {
        let frame = try await client.receive()
        try frame.requireFrame(id: id)
        received.append(frame)
      }
      #expect(received[2].texts.contains("Alpha"))
      #expect(received[2].focus?.editing == true)
      #expect(received[2].focus?.caretOffset == 5)
      #expect(received[6].texts.contains("Alpha"))
      #expect(received[6].texts.contains("Beta"))
      #expect(!received[6].texts.contains("AlphaBeta"))
      #expect(received[6].focus?.editing == true)
      #expect(received[6].focus?.caretOffset == 4)
      #expect(received[2].focus?.path != received[6].focus?.path)

      let closed = try await client.request(#"{"version":1,"id":"bye","op":"quit"}"#)
      #expect(closed.version == 1)
      #expect(closed.id == "bye")
      #expect(closed.status == "closed")
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func malformedRequestRecoversAndKeepsCorrelation() async throws {
    let outcome = try await runSession { client in
      try await client.send("not JSON\n" + #"{"version":1,"id":"recovered","op":"frame"}"#)
      let invalid = try await client.receive()
      #expect(invalid.version == 1)
      #expect(invalid.status == "error")
      #expect(invalid.id == nil)
      #expect(invalid.error == "invalid_request")
      try await client.receive().requireFrame(id: "recovered")
      let invalidSize = try await client.request(
        #"{"version":1,"id":"invalid-size","op":"resize","width":0,"height":600}"#)
      #expect(invalidSize.id == "invalid-size")
      #expect(invalidSize.error == "invalid_viewport")
      let recovered = try await client.request(#"{"version":1,"id":"recovered-again","op":"frame"}"#)
      try recovered.requireFrame(id: "recovered-again")
      #expect(recovered.viewport == .init(width: 800, height: 600))
      // Returning finishes stdin; EOF should close without an extra response.
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.contains("chroma-headless:"))
  }

  @Test func eofProcessesFinalUnterminatedRequest() async throws {
    let outcome = try await runSession { client in
      _ = try await client.input.write(#"{"version":1,"id":"last","op":"frame"}"#)
      try await client.input.finish()
      try await client.receive().requireFrame(id: "last")
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func emptyEOFProducesNoUnsolicitedOutput() async throws {
    try await runSession { _ in }.requireSuccess()
  }

  @Test func invalidCLIExitsNonzeroWithSeparateDiagnostics() async throws {
    let outcome = try await runSession(arguments: ["--viewport", "0x600"]) { _ in }
    #expect(outcome.status == .exited(1))
    #expect(outcome.diagnostics.contains("chroma-headless:"))
    #expect(outcome.diagnostics.contains("viewport"))
  }

  @Test func applicationLogsAndAsyncWorkProgressWhileStdinIsIdle() async throws {
    let outcome = try await runSession("CHROMA_HEADLESS_FIXTURE") { client in
      let initial = try await client.request(#"{"version":1,"id":"initial","op":"frame"}"#)
      try initial.requireFrame(id: "initial")
      #expect(initial.texts.contains("idle"))
      let position = try #require(initial.commands?.compactMap(\.text).first { $0.text == "Start async" }?.position)
      for phase in ["down", "up"] {
        let clicked = try await client.request(
          "{\"version\":1,\"id\":\"\(phase)\",\"op\":\"pointer\",\"phase\":\"\(phase)\",\"x\":\(position.x + 2),\"y\":\(position.y + 2)}"
        )
        try clicked.requireFrame(id: phase)
      }
      // No timer guess and no additional stdin: the async task must run before
      // its independently drained stderr marker allows the next request.
      try await client.diagnostics.wait(for: "fixture: async complete")
      let complete = try await client.request(#"{"version":1,"id":"complete","op":"frame"}"#)
      try complete.requireFrame(id: "complete")
      #expect(complete.texts.contains("complete"))
      let closed = try await client.request(#"{"version":1,"id":"quit","op":"quit"}"#)
      #expect(closed.status == "closed")
      #expect(closed.id == "quit")
    }
    try outcome.requireSuccess()
    for marker in [
      "initializer print", "frame observer print", "button callback print", "async print", "model deinit print",
    ] {
      #expect(outcome.diagnostics.contains("fixture: " + marker))
    }
  }

  @Test func stdoutAndStderrDrainBeforeResponsesAreConsumed() async throws {
    let count = 256
    let outcome = try await runSession(
      "CHROMA_HEADLESS_FIXTURE",
      environment: .inherit.updating(["CHROMA_FIXTURE_FLOOD_STDERR": "1"])
    ) { client in
      let requests = (0..<count).map { "{\"version\":1,\"id\":\"burst-\($0)\",\"op\":\"frame\"}" }
      try await client.send(requests.joined(separator: "\n"))
      try await client.input.finish()
      // The app flushes all 256 frames (over 200 KiB) before this exit marker.
      // Deliberately consume no replies until then: either undrained pipe would
      // prevent exit. No sleeps or assumptions about rendering speed are needed.
      try await client.diagnostics.wait(for: "fixture: model deinit print")
      for index in 0..<count {
        try await client.receive().requireFrame(id: "burst-\(index)")
      }
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.utf8.count > 300_000)
  }

  @Test func fixtureEOFFlushesApplicationAndDeinitializerLogs() async throws {
    let outcome = try await runSession("CHROMA_HEADLESS_FIXTURE") { client in
      try await client.request(#"{"version":1,"id":"before-eof","op":"frame"}"#).requireFrame(id: "before-eof")
    }
    try outcome.requireSuccess()
    for marker in ["initializer print", "frame observer print", "model deinit print"] {
      #expect(outcome.diagnostics.contains("fixture: " + marker))
    }
  }

  @Test func brokenStdoutReportsIOFailureInsteadOfSIGPIPE() async throws {
    let program = try executable("CHROMA_HEADLESS_FIXTURE")
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    defer { try? pipe.fileHandleForWriting.close() }
    let outputFD = pipe.fileHandleForWriting.fileDescriptor
    let outcome = try await withDeadline("broken stdout") {
      let result = try await Subprocess.run(
        program, arguments: ["--headless"], input: .inputWriter,
        output: .fileDescriptor(.init(rawValue: outputFD), closeAfterSpawningProcess: false),
        error: .sequence
      ) { execution in
        async let diagnostics: String = {
          var text = ""
          for try await line in execution.standardError.strings() { text += line }
          return text
        }()
        _ = try await execution.standardInputWriter.write(#"{"version":1,"op":"frame"}"# + "\n")
        try await execution.standardInputWriter.finish()
        return try await diagnostics
      }
      return ProcessOutcome(status: result.terminationStatus, diagnostics: result.closureResult)
    }
    #expect(outcome.status == .exited(1))
    #expect(outcome.diagnostics.contains("chroma-headless:"))
  }

  @Test func responseDeadlineCancelsReadAndReapsChild() async throws {
    let deadline = DeadlineProbe()
    do {
      _ = try await runSession { client in
        try await client.request(#"{"version":1,"id":"ready","op":"frame"}"#).requireFrame(id: "ready")
        await deadline.begin(client.pid)
        // The real app is now blocked on stdin. No response can arrive until we
        // send another request, so this must expire and cancel the pending read.
        _ = try await withDeadline("deliberately unanswered response", after: .milliseconds(100)) {
          try await client.receive()
        }
      }
      Issue.record("Expected the response deadline to expire")
    } catch let error as DeadlineExceeded {
      #expect(error.description == "Deadline exceeded: deliberately unanswered response")
      // Expected; runSession must have torn down and reaped the child first.
    }
    let start = try #require(await deadline.startedAt)
    #expect(start.duration(to: .now) < .seconds(3), "The outer session deadline must not mask a stuck reader")
    try requireReaped(try #require(await deadline.pid))
  }

  @Test func explicitCancellationReapsChildWithStdinStillOpen() async throws {
    let (ready, continuation) = AsyncStream.makeStream(of: Int32.self)
    let task = Task {
      defer { continuation.finish() }
      return try await runSession { client in
        try await client.request(#"{"version":1,"id":"ready","op":"frame"}"#).requireFrame(id: "ready")
        continuation.yield(client.pid)
        _ = try await client.receive()
      }
    }
    do {
      let pid = try await withDeadline("cancellation handshake") {
        var iterator = ready.makeAsyncIterator()
        return try #require(await iterator.next())
      }
      task.cancel()
      do {
        _ = try await task.value
        Issue.record("Expected cancellation of the blocked protocol read")
      } catch is CancellationError {
        // Cancellation does not return until Subprocess has cleaned up its child.
      }
      try requireReaped(pid)
    } catch {
      task.cancel()
      _ = await task.result
      throw error
    }
  }
}
