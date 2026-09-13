import Chroma
import Dispatch
import Foundation
import Logging
import NIOCore
import NIOPosix
import RemoteProtocol
import Synchronization

@MainActor
public final class RemoteServer {
  public var frameObserver: FrameObserver?
  public var keyBindings = KeyBindings()
  private var pointerState = InputState()
  private var clipboardEpoch: UInt64 = 0
  private struct EditorSnapshot {
    let text: String?
    let selection: Range<Int>?
    let leaf: WidgetID?
  }
  private struct PendingClipboard {
    enum Operation { case copy, cut, paste }
    let id: UInt64
    let operation: Operation
    let snapshot: EditorSnapshot
  }
  private var pendingClipboard: PendingClipboard?
  private var deferredInput: [RemoteMessage] = []
  private var logger = Logger(label: "chroma.remote.server")
  private let group: MultiThreadedEventLoopGroup
  private let connectionFactory: RemoteServerConnectionFactory
  private var serverChannel: Channel?
  private(set) var clientChannel: Channel?
  private let interaction = Interaction()
  private let frameProducer = FrameProducer()
  private var content: (any Block)?
  private var viewport: Size
  private var frameID: UInt64 = 0
  private var statistics = ServerStatistics()
  private var inputSequence: UInt64 = 0
  private var redrawScheduled = false
  private var framesPerSecond: Double = 30
  private var lastProducedAt: TimeInterval = 0
  private var requestPending = false
  private var waitsForChange = false
  private var frameDirty = true
  private var latestSnapshot: FrameSnapshot?
  private var heartbeat: Task<Void, Never>?
  private var lastSentCommands: [DrawCommand]?
  private var lastSentViewport: Size?
  private var connectionEpoch: UInt64 = 0
  private let wireEncoder = ConnectionFrameEncoder()
  private(set) var frameInFlight = false
  private let encodingQueue: DispatchQueue
  private struct FrameSnapshot: Sendable {
    let message: RemoteMessage
    let channel: Channel
    let drawDuration: TimeInterval
    let commandCount: Int
  }

  public convenience init(content: any Block, size: Size = Size(width: 800, height: 600)) {
    self.init(content: content, size: size, encodingQueue: DispatchQueue(label: "chroma.remote.frame-encoding"))
  }

  public convenience init<Content: Block>(
    size: Size = Size(width: 800, height: 600),
    @BlockBuilder content: @escaping @MainActor () -> Content
  ) {
    self.init(content: DeferredBlock(content: content), size: size)
  }

  init(content: any Block, size: Size = Size(width: 800, height: 600), encodingQueue: DispatchQueue) {
    self.encodingQueue = encodingQueue
    self.content = content
    self.viewport = size
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.connectionFactory = RemoteServerConnectionFactory()
    interaction.onRedrawRequested = { [weak self] in self?.invalidateFrame() }
  }

  public var boundPort: Int? { serverChannel?.localAddress?.port }

  public func start(host: String = "127.0.0.1", port: Int = 9328) throws {
    connectionFactory.server = self
    serverChannel = try ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 8)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer(connectionFactory.initialize)
      .bind(host: host, port: port).wait()
    logger.info("Chroma remote daemon listening", metadata: ["host": "\(host)", "port": "\(boundPort ?? port)"])
  }

  public func run() {
    #if os(macOS)
    RunLoop.main.run()
    #else
    dispatchMain()
    #endif
  }

  public func shutdown() throws {
    frameProducer.reset()
    let client = clientChannel
    clientChannel = nil
    connectionEpoch &+= 1
    try client?.close().wait()
    try serverChannel?.close().wait()
    try group.syncShutdownGracefully()
  }

  func receive(_ message: RemoteMessage, from channel: Channel) {
    guard channel.isActive else { return }
    if clientChannel == nil {
      logger.info("Remote client connected")
    }
    if let active = clientChannel, active !== channel {
      channel.close(promise: nil)
      return
    }
    clientChannel = channel
    if case .clipboard(let reply) = message {
      guard reply.isReply, let pending = pendingClipboard, pending.id == reply.id else { return }
      if reply.success {
        if pending.operation == .paste, let text = reply.text,
          pending.snapshot.leaf == interaction.editingLeaf,
          pending.snapshot.text == interaction.editingText,
          pending.snapshot.selection == interaction.textSelectionRange
        {
          render(input: InputState(textEvents: [.insert(text)]))
        }
        if pending.operation == .cut,
          pending.snapshot.text == interaction.editingText,
          pending.snapshot.selection == interaction.textSelectionRange,
          pending.snapshot.leaf == interaction.editingLeaf
        {
          render(input: InputState(textEvents: [.deleteForward]))
        }
      }
      finishClipboard()
      return
    }
    if pendingClipboard != nil {
      switch message {
      case .input, .key:
        guard deferredInput.count < 4096 else {
          channel.close(promise: nil)
          return
        }
        deferredInput.append(message)
        return
      default: break
      }
    }
    switch message {
    case .clipboard: break
    case .key(let sequence, let event):
      guard sequence > inputSequence else { return }
      inputSequence = sequence
      if keyBindings.prefersTextInsertion(
        chord: event.chord, text: event.text, isTextEditing: interaction.isTextEditing
      ), let text = event.text {
        render(input: InputState(textEvents: [.insert(text)]))
      } else if let chord = event.chord, let resolution = keyBindings.command(for: chord) {
        if let command = resolution { execute(command) }
      } else if interaction.isTextEditing, let text = event.text {
        render(input: InputState(textEvents: [.insert(text)]))
      }
    case .viewport(let size):
      guard RemoteFrameValidation.isValidViewport(size) else { return }
      viewport = size
      render()
    case .input(let sequence, let state):
      guard sequence > inputSequence else { return }
      pointerState = InputState(
        pointerPosition: state.pointerPosition, pointerPressPosition: state.pointerPressPosition,
        pointerDown: state.pointerDown)
      inputSequence = sequence
      render(input: state)
    case .frameRate(let fps):
      framesPerSecond = Double(fps)
    case .requestFrame:
      frameDirty = true
      waitsForChange = false
      requestPending = true
      scheduleRedraw()
    case .waitForFrame:
      waitsForChange = true
      requestPending = true
      heartbeat?.cancel()
      heartbeat = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        guard let self, self.requestPending else { return }
        self.waitsForChange = false
        self.scheduleRedraw()
      }
      scheduleRedraw()
    case .frame, .frameUnchanged:
      break
    }
  }

  private func execute(_ command: Command) {
    guard case .editing(let event) = command else {
      render(input: InputState(commands: [command]))
      return
    }
    switch event {
    case .copy, .cut, .paste:
      let text: String?
      if event == .paste {
        guard interaction.isTextEditing else { return }
        text = nil
      } else {
        text = event == .cut ? interaction.editableSelectionText() : interaction.copyText()
        guard let text, !text.isEmpty else { return }
      }
      let id = inputSequence
      clipboardEpoch &+= 1
      let epoch = clipboardEpoch
      pendingClipboard = PendingClipboard(
        id: id,
        operation: event == .cut ? .cut : (event == .paste ? .paste : .copy),
        snapshot: EditorSnapshot(
          text: interaction.editingText,
          selection: interaction.textSelectionRange, leaf: interaction.editingLeaf))
      do {
        let bytes = try RemoteWire.encode(.clipboard(ClipboardTransfer(id: id, text: text)))
        clientChannel?.writeAndFlush(bytes, promise: nil)
      } catch {
        finishClipboard()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self, self.pendingClipboard?.id == id, self.clipboardEpoch == epoch else { return }
        self.finishClipboard()
      }
    case .submit where !interaction.isTextEditing:
      render(input: InputState(commands: [.action(.activate)]))
    case .selectAll where !interaction.isTextEditing:
      interaction.selectAll(at: pointerState.pointerPosition)
      render()
    default:
      render(input: InputState(textEvents: [event]))
    }
  }

  private func finishClipboard() {
    pendingClipboard = nil
    while pendingClipboard == nil, !deferredInput.isEmpty, let channel = clientChannel {
      let next = deferredInput.removeFirst()
      receive(next, from: channel)
    }
  }

  func disconnected(_ channel: Channel) {
    guard clientChannel === channel else { return }
    clientChannel = nil
    frameProducer.reset()
    pendingClipboard = nil
    clipboardEpoch &+= 1
    deferredInput.removeAll()
    inputSequence = 0
    pointerState = InputState()
    connectionEpoch &+= 1
    redrawScheduled = false
    requestPending = false
    heartbeat?.cancel()
    heartbeat = nil
    latestSnapshot = nil
    frameDirty = true
    waitsForChange = false
    lastSentCommands = nil
    lastSentViewport = nil
    lastProducedAt = 0
    framesPerSecond = 30
  }

  private func invalidateFrame() {
    frameDirty = true
    scheduleRedraw()
  }

  private func scheduleRedraw() {
    guard requestPending else { return }
    if waitsForChange, !frameDirty, !frameProducer.needsAnimationFrame, let latestSnapshot,
      case .frame(_, _, let viewport, let commands) = latestSnapshot.message,
      lastSentViewport == viewport, lastSentCommands == commands
    {
      return
    }
    guard clientChannel != nil, !redrawScheduled else { return }
    redrawScheduled = true
    let epoch = connectionEpoch
    let delay = max(0, lastProducedAt + 1 / framesPerSecond - ProcessInfo.processInfo.systemUptime)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, self.connectionEpoch == epoch else { return }
      self.redrawScheduled = false
      guard self.requestPending, !self.frameInFlight else { return }
      if self.waitsForChange, !self.frameDirty, !self.frameProducer.needsAnimationFrame,
        let snapshot = self.latestSnapshot,
        case .frame(_, _, let viewport, let commands) = snapshot.message,
        self.lastSentViewport == viewport, self.lastSentCommands == commands
      {
        return
      }
      self.lastProducedAt = ProcessInfo.processInfo.systemUptime
      let snapshot = (self.frameDirty || self.frameProducer.needsAnimationFrame) ? self.render() : self.latestSnapshot
      if let snapshot { self.publishFrame(snapshot) }
    }
  }

  private func publishFrame(_ snapshot: FrameSnapshot) {
    heartbeat?.cancel()
    heartbeat = nil
    requestPending = false
    if case .frame(_, _, let viewport, let commands) = snapshot.message {
      if lastSentViewport == viewport, lastSentCommands == commands {
        if let bytes = try? RemoteWire.encode(.frameUnchanged) {
          snapshot.channel.writeAndFlush(bytes, promise: nil)
        }
        return
      }
      lastSentViewport = viewport
      lastSentCommands = commands
    }
    frameInFlight = true
    encodeFrame(snapshot)
  }

  @discardableResult
  private func render(input: InputState? = nil) -> FrameSnapshot? {
    guard let channel = clientChannel else { return nil }
    frameDirty = false
    let drawStarted = ProcessInfo.processInfo.systemUptime
    var input = input ?? pointerState
    input.pointerPosition = pointerState.pointerPosition
    input.pointerPressPosition = pointerState.pointerPressPosition
    input.pointerDown = pointerState.pointerDown
    var drawList = frameProducer.render(
      content: content, viewport: viewport, input: input,
      context: RenderContext(interaction: interaction),
      onChange: { [weak self] in self?.invalidateFrame() })
    frameObserver?(FrameObservation(drawList: drawList, viewport: viewport))
    _ = interaction.consumeRedrawRequest()
    drawList = drawList.culled(to: viewport)
    let drawDuration = ProcessInfo.processInfo.systemUptime - drawStarted
    frameID &+= 1
    let snapshot = FrameSnapshot(
      message: .frame(id: frameID, inputSequence: inputSequence, viewport: viewport, commands: drawList.commands),
      channel: channel, drawDuration: drawDuration, commandCount: drawList.commands.count)
    latestSnapshot = snapshot
    scheduleRedraw()
    return snapshot
  }

  private func encodeFrame(_ snapshot: FrameSnapshot) {
    let wireEncoder = self.wireEncoder
    encodingQueue.async { [weak self] in
      let started = ProcessInfo.processInfo.systemUptime
      let result = Result { try wireEncoder.encode(snapshot.message, channel: snapshot.channel) }
      let duration = ProcessInfo.processInfo.systemUptime - started
      DispatchQueue.main.async { [weak self] in
        self?.encodedFrame(snapshot, result: result, duration: duration)
      }
    }
  }

  private func encodedFrame(
    _ snapshot: FrameSnapshot, result: Result<EncodedFrame, Error>, duration: TimeInterval
  ) {
    guard clientChannel === snapshot.channel, snapshot.channel.isActive else {
      completeFrame()
      return
    }
    switch result {
    case .success(let encoded):
      let bytes = encoded.bytes
      statistics.imageBytes += encoded.imageBytes
      statistics.record(
        byteCount: bytes.readableBytes, commandCount: snapshot.commandCount,
        drawDuration: snapshot.drawDuration, encodeDuration: duration)
      snapshot.channel.writeAndFlush(bytes).whenComplete { [weak self] result in
        DispatchQueue.main.async {
          if case .failure(let error) = result {
            self?.logger.error("Remote frame write failed", metadata: ["error": "\(error)"])
            snapshot.channel.close(promise: nil)
          }
          self?.completeFrame()
        }
      }
    case .failure(let error):
      logger.error("Remote frame encoding failed", metadata: ["error": "\(error)"])
      snapshot.channel.close(promise: nil)
      completeFrame()
    }
  }

  private func completeFrame() {
    frameInFlight = false
    if requestPending { scheduleRedraw() }
  }
}

private final class RemoteServerConnectionFactory: Sendable {
  private static let logger = Logger(label: "chroma.remote.server.connection")
  @MainActor weak var server: RemoteServer?

  func initialize(channel: Channel) -> EventLoopFuture<Void> {
    Self.logger.info("Accepted remote TCP connection")
    return channel.eventLoop.makeCompletedFuture {
      let mailbox = RemoteInputMailbox { [weak self] message in
        self?.server?.receive(message, from: channel)
      }
      try channel.pipeline.syncOperations.addHandlers(
        ByteToMessageHandler(RemoteMessageDecoder()),
        RemoteServerHandler(
          mailbox: mailbox,
          onInactive: { [weak self] channel in
            DispatchQueue.main.async {
              self?.server?.disconnected(channel)
            }
          },
          onError: { error in
            Self.logger.error("Remote channel failed", metadata: ["error": "\(error)"])
          }))
    }
  }
}

private final class RemoteServerHandler: ChannelInboundHandler, Sendable {
  typealias InboundIn = DecodedRemoteMessage
  private let mailbox: RemoteInputMailbox
  private let onInactive: @Sendable (Channel) -> Void
  private let onError: @Sendable (Error) -> Void

  init(
    mailbox: RemoteInputMailbox,
    onInactive: @escaping @Sendable (Channel) -> Void,
    onError: @escaping @Sendable (Error) -> Void
  ) {
    self.mailbox = mailbox
    self.onInactive = onInactive
    self.onError = onError
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let decoded = unwrapInboundIn(data)
    if !mailbox.enqueue(decoded.message, byteCount: decoded.byteCount) {
      context.close(promise: nil)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    mailbox.close()
    onInactive(context.channel)
  }
  func errorCaught(context: ChannelHandlerContext, error: Error) {
    onError(error)
    context.close(promise: nil)
  }
}

private final class ConnectionFrameEncoder: Sendable {
  private struct State: Sendable {
    var channel: Channel?
    var images = RemoteImageCache()
  }
  private let state = Mutex(State())

  func encode(_ message: RemoteMessage, channel: Channel) throws -> EncodedFrame {
    try state.withLock { state in
      if state.channel !== channel {
        state.channel = channel
        state.images = RemoteImageCache()
      }
      let before = state.images.transmittedPixelBytes
      let bytes = try RemoteWire.encode(message, images: &state.images)
      return EncodedFrame(bytes: bytes, imageBytes: state.images.transmittedPixelBytes - before)
    }
  }
}

private struct EncodedFrame: Sendable {
  let bytes: ByteBuffer
  let imageBytes: Int
}
