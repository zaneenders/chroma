import ChromaHeadless
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
        let frame = try await client.request(.init(id: .init(rawValue: id), op: .frame))
        try frame.requireFrame(id: id)
        #expect(frame.viewport == .init(width: 800, height: 600))
        #expect(frame.texts.contains("First"))
        #expect(frame.texts.contains("Second"))
      }

      // One write deliberately sends requests faster than frames can be rendered.
      let burst: [HeadlessRequest] = [
        .init(id: "focus-first", op: .key, key: .tab),
        .init(id: "edit-first", op: .key, key: .enter),
        .init(id: "text-first", op: .key, text: "Alpha"),
        .init(id: "focus-second", op: .key, key: .tab),
        .init(id: "edit-second", op: .key, key: .enter),
        .init(id: "text-second", op: .key, text: "Beta"),
        .init(id: "snapshot", op: .frame),
      ]
      try await client.send(burst)
      var received: [HeadlessResponse] = []
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

      let closed = try await client.request(.init(id: "bye", op: .quit))
      #expect(closed.version == 1)
      #expect(closed.id == "bye")
      #expect(closed.status == .closed)
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func malformedRequestRecoversAndKeepsCorrelation() async throws {
    let outcome = try await runSession { client in
      try await client.sendRaw(Data("not JSON\n".utf8) + HeadlessRequest(id: "recovered", op: .frame).encoded())
      let invalid = try await client.receive()
      #expect(invalid.version == 1)
      #expect(invalid.status == .error)
      #expect(invalid.id == nil)
      #expect(invalid.error == .invalidRequest)
      try await client.receive().requireFrame(id: "recovered")
      let invalidSize = try await client.request(
        .init(id: "invalid-size", op: .resize, width: 0, height: 600))
      #expect(invalidSize.id == "invalid-size")
      #expect(invalidSize.error == .invalidViewport)
      let recovered = try await client.request(.init(id: "recovered-again", op: .frame))
      try recovered.requireFrame(id: "recovered-again")
      #expect(recovered.viewport == .init(width: 800, height: 600))
      // Returning finishes stdin; EOF should close without an extra response.
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.contains("chroma-headless:"))
  }

  @Test func eofProcessesFinalUnterminatedRequest() async throws {
    let outcome = try await runSession { client in
      try await client.send(.init(id: "last", op: .frame), terminated: false)
      try await client.input.finish()
      try await client.receive().requireFrame(id: "last")
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func emptyEOFClosesSuccessfully() async throws {
    try await runSession { _ in }.requireSuccess()
  }

  @Test func invalidCLIExitsNonzeroWithSeparateDiagnostics() async throws {
    let outcome = try await runSession(arguments: ["--viewport", "0x600"]) { _ in }
    #expect(outcome.status == .exited(1))
    #expect(outcome.diagnostics.contains("chroma-headless:"))
    #expect(outcome.diagnostics.contains("viewport"))
  }

  @Test func missingViewportExitsNonzeroWithUsage() async throws {
    let outcome = try await runSession(arguments: []) { _ in }
    #expect(outcome.status == .exited(1))
    #expect(outcome.diagnostics.contains("Usage:"))
    #expect(outcome.diagnostics.contains("--viewport WIDTHxHEIGHT"))
  }

  @Test func allChangesContinuouslyEmitsUnchangedFrames() async throws {
    let outcome = try await runSession("HeadlessProcessFixture", arguments: ["--viewport", "800x600", "--all-changes"]) { client in
      let first = try await client.frames.next()
      let second = try await client.frames.next()
      let third = try await client.frames.next()
      #expect(first.id == nil)
      #expect(second.status == .frame)
      #expect(third.status == .frame)
      #expect(first.commands == second.commands)
      #expect(second.commands == third.commands)
    }
    try outcome.requireSuccess()
  }

  @Test func defaultDoesNotRepeatIdleFrames() async throws {
    let outcome = try await runSession("HeadlessProcessFixture", arguments: ["--viewport", "800x600"]) { client in
      _ = try await client.frames.next()
      do {
        _ = try await withDeadline("idle frame", after: .milliseconds(100)) {
          try await client.frames.next()
        }
        Issue.record("Unexpected repeated idle frame")
      } catch is DeadlineExceeded {}
      let response = try await client.request(.init(id: "alive", op: .frame))
      try response.requireFrame(id: "alive")
    }
    try outcome.requireSuccess()
  }

  @Test func emitsInitialFrameWithoutStdinRequest() async throws {
    let outcome = try await runSession("HeadlessProcessFixture") { client in
      let frame = try await client.waitForText("idle")
      #expect(frame.status == .frame)
      #expect(frame.id == nil)
      #expect(frame.viewport == .init(width: 800, height: 600))
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func asyncWorkUpdatesFrameworkStdout() async throws {
    let outcome = try await runSession("HeadlessProcessFixture") { client in
      let initialID = UUID()
      let initial = try await client.request(.init(id: .init(rawValue: initialID.uuidString), op: .frame))
      try initial.requireFrame(id: initialID)
      #expect(initial.texts.contains("idle"))
      let position = try #require(initial.commands?.compactMap { command in
        if case .text(let position, "Start async", _, _) = command { return position }
        return nil
      }.first)
      for phase in [HeadlessPointerPhase.down, .up] {
        let id = UUID()
        let clicked = try await client.request(
          .init(id: .init(rawValue: id.uuidString), op: .pointer, x: position.x + 2, y: position.y + 2, phase: phase)
        )
        try clicked.requireFrame(id: id)
      }
      let complete = try await client.waitForText("complete")
      #expect(complete.texts.contains("complete"))
      let quitID = UUID()
      let closed = try await client.request(.init(id: .init(rawValue: quitID.uuidString), op: .quit))
      #expect(closed.status == .closed)
      #expect(closed.id?.rawValue == quitID.uuidString)
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func timerUpdatesFrameworkStdout() async throws {
    let outcome = try await runSession("HeadlessProcessFixture") { client in
      let initialID = UUID()
      let initial = try await client.request(.init(id: .init(rawValue: initialID.uuidString), op: .frame))
      try initial.requireFrame(id: initialID)
      #expect(initial.texts.contains("Tick: 0"))
      let position = try #require(initial.commands?.compactMap { command in
        if case .text(let position, "Start timer", _, _) = command { return position }
        return nil
      }.first)
      for phase in [HeadlessPointerPhase.down, .up] {
        let id = UUID()
        try await client.request(
          .init(id: .init(rawValue: id.uuidString), op: .pointer, x: position.x + 2, y: position.y + 2, phase: phase)
        ).requireFrame(id: id)
      }
      let updated = try await client.waitForText("Tick: 3")
      #expect(updated.texts.contains("Tick: 3"))
      #expect(!updated.texts.contains("Tick: 0"))
      let unchangedID = UUID()
      let unchanged = try await client.request(.init(id: .init(rawValue: unchangedID.uuidString), op: .frame))
      try unchanged.requireFrame(id: unchangedID)
      #expect(unchanged.commands == updated.commands)
      let quitID = UUID()
      let closed = try await client.request(.init(id: .init(rawValue: quitID.uuidString), op: .quit))
      #expect(closed.status == .closed)
      #expect(closed.id?.rawValue == quitID.uuidString)
    }
    try outcome.requireSuccess()

  }

  @Test func stdoutBurstDrainsBeforeResponsesAreConsumed() async throws {
    let count = 256
    let outcome = try await runSession("HeadlessProcessFixture") { client in
      let requests = (0..<count).map { HeadlessRequest(id: .init(rawValue: "burst-\($0)"), op: .frame) }
      try await client.send(requests)
      try await client.input.finish()
      try await client.responses.waitForEOF()
      for index in 0..<count {
        try await client.receive().requireFrame(id: "burst-\(index)")
      }
    }
    try outcome.requireSuccess()
    #expect(outcome.diagnostics.isEmpty)
  }

  @Test func brokenStdoutReportsIOFailureInsteadOfSIGPIPE() async throws {
    let program = try executable("HeadlessProcessFixture")
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    defer { try? pipe.fileHandleForWriting.close() }
    let outputFD = pipe.fileHandleForWriting.fileDescriptor
    let outcome = try await withDeadline("broken stdout") {
      let result = try await Subprocess.run(
        program, arguments: ["--viewport", "800x600"], input: .inputWriter,
        output: .fileDescriptor(.init(rawValue: outputFD), closeAfterSpawningProcess: false),
        error: .sequence
      ) { execution in
        async let diagnostics: String = {
          var text = ""
          for try await line in execution.standardError.strings() { text += line }
          return text
        }()
        _ = try await execution.standardInputWriter.write(HeadlessRequest(op: .frame).encoded())
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
        try await client.request(.init(id: "ready", op: .frame)).requireFrame(id: "ready")
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
        try await client.request(.init(id: "ready", op: .frame)).requireFrame(id: "ready")
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
