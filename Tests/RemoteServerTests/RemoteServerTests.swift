import Foundation
import NIOCore
import NIOEmbedded
import RemoteProtocol
import Testing

@testable import Chroma
@testable import RemoteServer

@MainActor
struct RemoteServerTests {
  private func reply(from channel: EmbeddedChannel) async throws -> RemoteMessage {
    var images = RemoteImageCache()
    return try await reply(from: channel, images: &images)
  }

  private func reply(from channel: EmbeddedChannel, images: inout RemoteImageCache) async throws
    -> RemoteMessage
  {
    for _ in 0..<500 {
      channel.embeddedEventLoop.run()
      if var bytes = try channel.readOutbound(as: ByteBuffer.self) {
        return try #require(try RemoteWire.decode(from: &bytes, images: &images))
      }
      try await Task.sleep(for: .milliseconds(2))
    }
    throw MissingReply()
  }
  private struct MissingReply: Error {}

  @Test func creditsUnchangedFramesAndReconnect() async throws {
    let server = RemoteServer(content: EmptyBlock())
    let first = EmbeddedChannel()
    let second = EmbeddedChannel()
    try await first.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    try await second.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(first)
      server.disconnected(second)
      _ = try? first.finish()
      _ = try? second.finish()
      try? server.shutdown()
    }
    server.receive(.viewport(Size(width: 800, height: 600)), from: first)
    try await Task.sleep(for: .milliseconds(40))
    #expect(try first.readOutbound(as: ByteBuffer.self) == nil)
    server.receive(.requestFrame, from: first)
    guard case .frame = try await reply(from: first) else {
      Issue.record("First credit must produce a full frame")
      return
    }
    server.receive(.requestFrame, from: first)
    #expect(try await reply(from: first) == .frameUnchanged)
    try await Task.sleep(for: .milliseconds(40))
    #expect(try first.readOutbound(as: ByteBuffer.self) == nil)
    server.disconnected(first)
    server.receive(.requestFrame, from: second)
    guard case .frame = try await reply(from: second) else {
      Issue.record("New connection must receive a full frame")
      return
    }
  }
}

@MainActor private final class PointerRecorder {
  var inputs: [InputState] = []
}

private struct PointerRecordingBlock: PrimitiveBlock {
  let recorder: PointerRecorder
  @MainActor func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  @MainActor func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
    recorder.inputs.append(context.interaction.input)
  }
}

extension RemoteServerTests {
  @Test func presentationAndKeyboardPreservePointerWithoutReplayingEdges() async throws {
    let recorder = PointerRecorder()
    let server = RemoteServer(content: PointerRecordingBlock(recorder: recorder))
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    let position = Point(x: 100, y: 120)
    let origin = Point(x: 90, y: 110)
    server.receive(
      .input(
        sequence: 1,
        state: InputState(
          pointerPosition: position, pointerPressPosition: origin, pointerDown: true,
          pointerPressed: true, scrollDelta: Point(x: 0, y: 3))), from: channel)
    #expect(recorder.inputs.last?.pointerPressed == true)
    server.receive(.requestFrame, from: channel)
    _ = try await reply(from: channel)
    let presented = try #require(recorder.inputs.last)
    #expect(presented.pointerPosition == position)
    #expect(presented.pointerPressPosition == origin)
    #expect(presented.pointerDown)
    #expect(!presented.pointerPressed && !presented.pointerReleased)
    #expect(presented.scrollDelta == .zero)
    server.keyBindings = KeyBindings { bind("j", to: .navigation(.down)) }
    server.receive(.key(sequence: 2, event: RemoteKeyEvent(chord: KeyChord("j"))), from: channel)
    #expect(recorder.inputs.last?.pointerPosition == position)
    #expect(recorder.inputs.last?.pointerDown == true)
    server.receive(.viewport(Size(width: 400, height: 300)), from: channel)
    #expect(recorder.inputs.last?.pointerPosition == position)
    #expect(recorder.inputs.last?.commands.isEmpty == true)
    server.receive(
      .input(
        sequence: 3,
        state: InputState(
          pointerPosition: position, pointerPressPosition: origin, pointerReleased: true)), from: channel)
    server.receive(.requestFrame, from: channel)
    _ = try await reply(from: channel)
    #expect(recorder.inputs.last?.pointerDown == false)
    #expect(recorder.inputs.last?.pointerReleased == false)
  }
}

extension RemoteServerTests {
  @Test func presentationCreditsRespectFrameRate() async throws {
    let server = RemoteServer(content: EmptyBlock())
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.frameRate(30), from: channel)
    server.receive(.requestFrame, from: channel)
    _ = try await reply(from: channel)
    let clock = ContinuousClock()
    let started = clock.now
    for _ in 0..<30 {
      server.receive(.requestFrame, from: channel)
      #expect(try await reply(from: channel) == .frameUnchanged)
    }
    #expect(started.duration(to: clock.now) >= .seconds(30 / 30.5))
    try await Task.sleep(for: .milliseconds(150))
    #expect(try channel.readOutbound(as: ByteBuffer.self) == nil)
  }

  @Test func viewportChangeReusesImagePixels() async throws {
    let image = try ImageResource(
      id: ImageID("test"), width: 2, height: 2,
      rgba8: Data(repeating: 255, count: 16))
    let server = RemoteServer(content: Image(image))
    let channel = EmbeddedChannel()
    var images = RemoteImageCache()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.requestFrame, from: channel)
    guard case .frame = try await reply(from: channel, images: &images) else {
      Issue.record("First credit must produce a full frame")
      return
    }
    #expect(images.transmittedPixelBytes == image.rgba8.count)
    let resized = Size(width: 820, height: 520)
    server.receive(.viewport(resized), from: channel)
    server.receive(.requestFrame, from: channel)
    guard case .frame(_, _, let viewport, let commands) = try await reply(from: channel, images: &images) else {
      Issue.record("Viewport change must produce a full frame")
      return
    }
    #expect(viewport == resized)
    #expect(!commands.isEmpty)
    #expect(images.transmittedPixelBytes == image.rgba8.count)
  }
}

@MainActor private final class EditorRecorder {
  var text = ""
}

private struct EditingBlock: PrimitiveBlock {
  let recorder: EditorRecorder
  @MainActor func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  @MainActor func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
    context.interaction.beginGroup(.vertical, rect: rect)
    _ = context.interaction.textInputBehavior(
      id: WidgetID("editor"), rect: rect, text: recorder.text,
      onChange: { recorder.text = $0 })
    context.interaction.endGroup()
  }
}

extension RemoteServerTests {
  @Test func keyboardUsesTextOrExplicitShortcutsWithoutAnEditingOverlay() async throws {
    let recorder = EditorRecorder()
    let server = RemoteServer(content: EditingBlock(recorder: recorder))
    server.keyBindings = KeyBindings {
      bind("a", modifiers: .command, to: .editing(.selectAll))
      disable("x")
      bind(.space, to: .action(.activate))
      bind("j", to: .navigation(.down))
      bind("f", to: .application("picker.previous"))
    }
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.viewport(Size(width: 400, height: 100)), from: channel)
    server.receive(.input(sequence: 1, state: InputState(commands: [.action(.activate)])), from: channel)
    for (offset, character) in "jfd kls".enumerated() {
      server.receive(
        .key(
          sequence: UInt64(offset + 2),
          event: RemoteKeyEvent(
            chord: character == " " ? KeyChord(.space) : KeyChord(character), text: String(character))), from: channel)
    }
    #expect(recorder.text == "jfd kls")
    server.receive(.key(sequence: 20, event: RemoteKeyEvent(chord: KeyChord("x"), text: "x")), from: channel)
    #expect(recorder.text == "jfd kls")
    server.receive(
      .key(
        sequence: 21,
        event: RemoteKeyEvent(
          chord: KeyChord("a", modifiers: .command), text: "a")), from: channel)
    server.receive(.key(sequence: 22, event: RemoteKeyEvent(chord: nil, text: "replacement")), from: channel)
    #expect(recorder.text == "replacement")
  }
}

extension RemoteServerTests {
  @Test func commandEnterReachesBackendAsApplicationCommand() async throws {
    let recorder = PointerRecorder()
    let server = RemoteServer(content: PointerRecordingBlock(recorder: recorder))
    let submit = Command.application("test.composer.submit")
    server.keyBindings = KeyBindings { bind(.enter, modifiers: .command, to: submit) }
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.key(sequence: 1, event: RemoteKeyEvent(chord: KeyChord(.enter, modifiers: .command))), from: channel)
    #expect(recorder.inputs.last?.commands == [submit])
    #expect(recorder.inputs.last?.textEvents.isEmpty == true)
  }
}

extension RemoteServerTests {
  @Test func enterActivatesFocusedButtonOutsideEditing() async throws {
    var activations = 0
    let server = RemoteServer(content: Button("Activate", id: WidgetID("button")) { activations += 1 })
    server.keyBindings = KeyBindings { bind(.enter, to: .editing(.submit)) }
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.viewport(Size(width: 400, height: 100)), from: channel)
    server.receive(.key(sequence: 1, event: RemoteKeyEvent(chord: KeyChord(.enter))), from: channel)
    #expect(activations == 1)
  }

  @Test func enterStartsEditingThenSubmitsInsteadOfReactivating() async throws {
    let recorder = EditorRecorder()
    let server = RemoteServer(content: EditingBlock(recorder: recorder))
    server.keyBindings = KeyBindings { bind(.enter, to: .editing(.submit)) }
    let channel = EmbeddedChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 9328)).get()
    defer {
      server.disconnected(channel)
      _ = try? channel.finish()
      try? server.shutdown()
    }
    server.receive(.viewport(Size(width: 400, height: 100)), from: channel)
    server.receive(.key(sequence: 1, event: RemoteKeyEvent(chord: KeyChord(.enter))), from: channel)
    server.receive(.key(sequence: 2, event: RemoteKeyEvent(chord: nil, text: "edited")), from: channel)
    #expect(recorder.text == "edited")
    server.receive(.key(sequence: 3, event: RemoteKeyEvent(chord: KeyChord(.enter))), from: channel)
    server.receive(.key(sequence: 4, event: RemoteKeyEvent(chord: nil, text: "ignored")), from: channel)
    #expect(recorder.text == "edited")
  }
}
