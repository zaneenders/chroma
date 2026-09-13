import Dispatch
import Foundation
import NIOCore
import NIOPosix
import Observation
import RemoteProtocol
import Synchronization
import Testing

@testable import Chroma
@testable import RemoteServer

private final class Replies: ChannelInboundHandler, Sendable {
  typealias InboundIn = DecodedRemoteMessage
  private let messages = Mutex<[RemoteMessage]>([])
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let message = unwrapInboundIn(data).message
    messages.withLock { $0.append(message) }
  }
  func pop() -> RemoteMessage? {
    messages.withLock { messages in
      messages.isEmpty ? nil : messages.removeFirst()
    }
  }
  func errorCaught(context: ChannelHandlerContext, error: Error) {
    context.close(promise: nil)
  }
}

@MainActor
private func eventually(_ predicate: () -> Bool) async throws {
  for _ in 0..<1000 {
    if predicate() { return }
    try await Task.sleep(for: .milliseconds(2))
  }
  throw LoopbackTimeout()
}
private struct LoopbackTimeout: Error {}

@MainActor
private final class Peer {
  let channel: Channel
  let replies: Replies
  init(group: MultiThreadedEventLoopGroup, port: Int) async throws {
    let replies = Replies()
    self.replies = replies
    channel = try await ClientBootstrap(group: group)
      .connectTimeout(.seconds(2))
      .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandlers(
            ByteToMessageHandler(RemoteMessageDecoder()), replies)
        }
      }
      .connect(host: "127.0.0.1", port: port).get()
  }
  func send(_ message: RemoteMessage) async throws {
    try await channel.writeAndFlush(RemoteWire.encode(message)).get()
  }
  func reply() async throws -> RemoteMessage {
    for _ in 0..<1000 {
      if let message = replies.pop() { return message }
      try await Task.sleep(for: .milliseconds(2))
    }
    throw LoopbackTimeout()
  }
  func close() async throws { try await channel.close().get() }
}

@MainActor
struct RemoteLoopbackTests {
  @Test(.timeLimit(.minutes(1))) func reconnectAndShutdown() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let server = RemoteServer(content: EmptyBlock())
    defer {
      try? server.shutdown()
      stopGroup(group)
    }
    try server.start(port: 0)
    let port = try #require(server.boundPort)
    let first = try await Peer(group: group, port: port)
    try await first.send(.requestFrame)
    guard case .frame = try await first.reply() else {
      Issue.record("Expected full frame")
      return
    }
    try await first.send(.requestFrame)
    #expect(try await first.reply() == .frameUnchanged)
    try await first.close()
    try await eventually { server.clientChannel == nil }
    let second = try await Peer(group: group, port: port)
    try await second.send(.requestFrame)
    guard case .frame = try await second.reply() else {
      Issue.record("Reconnect needs full frame")
      return
    }
    try await second.close()
    try await eventually { server.clientChannel == nil }
  }

  @Test(.timeLimit(.minutes(1))) func disconnectWhileEncodingDoesNotPoisonReconnect() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let queue = DispatchQueue(label: "test.held-encoder")
    queue.suspend()
    var suspended = true
    let server = RemoteServer(content: EmptyBlock(), encodingQueue: queue)
    defer {
      if suspended { queue.resume() }
      try? server.shutdown()
      stopGroup(group)
    }
    try server.start(port: 0)
    let port = try #require(server.boundPort)
    let first = try await Peer(group: group, port: port)
    try await first.send(.requestFrame)
    try await eventually { server.frameInFlight }
    try await first.close()
    try await eventually { server.clientChannel == nil }
    let second = try await Peer(group: group, port: port)
    try await second.send(.viewport(Size(width: 321, height: 123)))
    try await second.send(.requestFrame)
    try await eventually { server.clientChannel != nil }
    queue.resume()
    suspended = false
    guard case .frame(_, _, let viewport, _) = try await second.reply() else {
      Issue.record("Expected new connection frame")
      return
    }
    #expect(viewport == Size(width: 321, height: 123))
    try await second.send(.requestFrame)
    #expect(try await second.reply() == .frameUnchanged)
    try await second.close()
  }

  @Test(.timeLimit(.minutes(1))) func disconnectCancelsPendingClipboardAndDeferredKeys() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let editor = LoopbackEditor()
    let server = RemoteServer(content: LoopbackEditingBlock(editor: editor))
    server.keyBindings = KeyBindings { bind("v", modifiers: .command, to: .editing(.paste)) }
    defer {
      try? server.shutdown()
      stopGroup(group)
    }
    try server.start(port: 0)
    let port = try #require(server.boundPort)
    let first = try await Peer(group: group, port: port)
    try await first.send(.viewport(Size(width: 400, height: 100)))
    try await first.send(.input(sequence: 1, state: InputState(commands: [.action(.activate)])))
    try await first.send(.key(sequence: 2, event: RemoteKeyEvent(chord: KeyChord("v", modifiers: .command))))
    guard case .clipboard(let transfer) = try await first.reply() else {
      Issue.record("Expected clipboard request")
      return
    }
    #expect(!transfer.isReply)
    try await first.send(.key(sequence: 3, event: RemoteKeyEvent(chord: nil, text: "stale")))
    try await first.send(.requestFrame)
    _ = try await first.reply()
    #expect(editor.text.isEmpty)
    try await first.close()
    try await eventually { server.clientChannel == nil }
    let second = try await Peer(group: group, port: port)
    try await second.send(.key(sequence: 1, event: RemoteKeyEvent(chord: nil, text: "fresh")))
    try await second.send(.requestFrame)
    _ = try await second.reply()
    #expect(editor.text == "fresh")
    try await second.close()
  }

  @Test(.timeLimit(.minutes(1))) func shutdownClosesConnectedPeer() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let server = RemoteServer(content: EmptyBlock())
    var stopped = false
    defer {
      if !stopped { try? server.shutdown() }
      stopGroup(group)
    }
    try server.start(port: 0)
    let peer = try await Peer(group: group, port: #require(server.boundPort))
    try await peer.send(.requestFrame)
    _ = try await peer.reply()
    try server.shutdown()
    stopped = true
    try await eventually { !peer.channel.isActive }
  }
}

@MainActor private final class LoopbackEditor { var text = "" }
private struct LoopbackEditingBlock: PrimitiveBlock {
  let editor: LoopbackEditor
  @MainActor func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  @MainActor func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
    context.interaction.beginGroup(.vertical, rect: rect)
    _ = context.interaction.registerTextInput(
      id: WidgetID("editor"), rect: rect, text: { editor.text }, onChange: { editor.text = $0 })
    context.interaction.endGroup()
  }
}

private func stopGroup(_ group: MultiThreadedEventLoopGroup) {
  try? group.syncShutdownGracefully()
}

extension RemoteLoopbackTests {
  @Test func longPollSleepsUntilObservedStateChanges() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let model = LongPollModel()
    let server = RemoteServer { model.color }
    defer {
      try? server.shutdown()
      stopGroup(group)
    }
    try server.start(port: 0)
    let peer = try await Peer(group: group, port: #require(server.boundPort))
    try await peer.send(.waitForFrame)
    guard case .frame = try await peer.reply() else {
      Issue.record("Expected initial frame")
      return
    }
    try await peer.send(.waitForFrame)
    try await Task.sleep(for: .milliseconds(100))
    #expect(peer.replies.pop() == nil)
    model.color = .yellow
    guard case .frame(_, _, _, let commands) = try await peer.reply() else {
      Issue.record("Expected observed update")
      return
    }
    #expect(!commands.isEmpty)
    try await peer.close()
  }
}

@MainActor
@Observable
private final class LongPollModel {
  var color = Color.white
}

private struct TimelineProbe: PrimitiveBlock {
  let samples: TimelineSamples
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let frame = context.animationFrame()
    samples.times.append(frame.timestamp)
    drawList.text(String(frame.timestamp), at: .zero, color: .white)
  }
}

@MainActor private final class TimelineSamples {
  var times: [Double] = []
}

extension RemoteLoopbackTests {
  @Test func animationUsesRemoteCadenceAndWaitsForFrameDemand() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let samples = TimelineSamples()
    let server = RemoteServer(content: TimelineProbe(samples: samples))
    defer {
      try? server.shutdown()
      stopGroup(group)
    }
    try server.start(port: 0)
    let peer = try await Peer(group: group, port: #require(server.boundPort))
    try await peer.send(.frameRate(10))
    try await peer.send(.waitForFrame)
    _ = try await peer.reply()
    let first = try #require(samples.times.last)
    let count = samples.times.count
    try await Task.sleep(for: .milliseconds(150))
    #expect(samples.times.count == count)
    try await peer.send(.waitForFrame)
    _ = try await peer.reply()
    let second = try #require(samples.times.last)
    #expect(second - first >= 0.1)
    try await peer.send(.waitForFrame)
    _ = try await peer.reply()
    let third = try #require(samples.times.last)
    #expect(third - second >= 0.09)
    try await peer.close()
  }
}
