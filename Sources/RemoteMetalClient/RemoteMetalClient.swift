#if METAL_BACKEND

import AppKit
import Chroma
import Metal
import MetalBackend
import MetalKit
import NIOCore
import NIOPosix
import RemoteProtocol

@MainActor
public final class RemoteMetalClient: NSObject, MTKViewDelegate, NSWindowDelegate {
  private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  private var channel: Channel?
  private var endpoint: (host: String, port: Int)?
  private var connectionGeneration = UUID()
  private var reconnectTimer: Timer?
  private var reconnectDelay: TimeInterval = 1
  private var awaitingReconnectFrame = false
  private let connectedTitle: String
  private let queue: MTLCommandQueue
  private let displayRenderer: MetalDisplayListRenderer
  private let view: ChromaInputView
  private let banner = NotificationBanner()
  private let window: NSWindow
  private var frameState = RemoteFrameState()
  private var latestFrame: (viewport: Size, commands: [DrawCommand])? { frameState.latest }
  private var clipboardGenerations = ClipboardGenerations()
  private var statistics = ClientStatistics()
  private var inputSequence: UInt64 = 0
  private var isShuttingDown = false
  private var requestStartedAt: TimeInterval = 0
  private var frameRequestTimer: Timer?
  private var frameRequestOutstanding: Bool {
    get { frameState.requestOutstanding }
    set { frameState.requestOutstanding = newValue }
  }
  private var requestedFramesPerSecond: Double = 30
  private var lifetimeRetain: RemoteMetalClient?

  public init(size: Size = Size(width: 800, height: 600), title: String = "Chroma Remote") throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw BackendError.unavailable(backend: "Remote Metal", reason: "no compatible GPU was found")
    }
    self.connectedTitle = title
    self.queue = queue
    let frame = CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height))
    let view = ChromaInputView(frame: frame, device: device)
    view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    self.view = view

    self.displayRenderer = try MetalDisplayListRenderer(device: device, pixelFormat: view.colorPixelFormat)
    self.window = NSWindow(
      contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    super.init()
    window.title = title
    window.contentView = view
    banner.onChange = { [weak self] in self?.view.needsDisplay = true }
    window.delegate = self
    window.center()
    view.delegate = self
    view.onInputAvailable = { [weak self] in self?.sendPendingInput() }
    view.onRemoteKey = { [weak self] chord, text in
      guard let self, !self.isShuttingDown, self.channel?.isActive == true else { return }
      self.inputSequence &+= 1
      self.clipboardGenerations.record(sequence: self.inputSequence, generation: NSPasteboard.general.changeCount)
      self.send(.key(sequence: self.inputSequence, event: RemoteKeyEvent(chord: chord, text: text)))
    }
  }

  public func connect(
    host: String = "127.0.0.1", port: Int = 9328, framesPerSecond: Double = 30
  ) throws {
    requestedFramesPerSecond = framesPerSecond.isFinite ? min(240, max(1, framesPerSecond)) : 30
    endpoint = (host, port)
    let generation = UUID()
    connectionGeneration = generation
    let channel = try openConnection(host: host, port: port, generation: generation).wait()
    try activate(channel)
  }

  private func openConnection(host: String, port: Int, generation: UUID) -> EventLoopFuture<Channel> {
    ClientBootstrap(group: group)
      .connectTimeout(.seconds(5))
      .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
      .channelInitializer { [weak self] channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandlers(
            ByteToMessageHandler(RemoteMessageDecoder()),
            RemoteClientHandler(
              onMessage: { [weak self] message, byteCount, decodeDuration in
                DispatchQueue.main.async {
                  guard let self, self.connectionGeneration == generation else { return }
                  self.receive(message, byteCount: byteCount, decodeDuration: decodeDuration)
                }
              },
              onInactive: { [weak self] in
                DispatchQueue.main.async {
                  guard let self, self.connectionGeneration == generation else { return }
                  self.connectionClosed()
                }
              }))
        }
      }
      .connect(host: host, port: port)
  }

  private func activate(_ channel: Channel) throws {
    self.channel = channel
    frameRequestOutstanding = false
    clipboardGenerations.removeAll()
    _ = view.frameInput()
    channel.write(try RemoteWire.encode(.frameRate(Float(requestedFramesPerSecond))), promise: nil)
    let write = channel.writeAndFlush(try RemoteWire.encode(.viewport(currentViewport)))
    write.whenFailure { error in print("Initial viewport write failed: \(error)") }
    startFrameRequests()
  }

  private func startFrameRequests() {
    frameRequestTimer?.invalidate()
    let timer = Timer(timeInterval: 1 / requestedFramesPerSecond, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.requestFrameIfNeeded() }
    }
    RunLoop.main.add(timer, forMode: .common)
    frameRequestTimer = timer
    requestFrameIfNeeded()
  }

  private func requestFrameIfNeeded() {
    guard !isShuttingDown, let channel, channel.isActive else { return }
    if frameRequestOutstanding {
      if FrameResponseDeadline.hasExpired(since: requestStartedAt) {
        channel.close(promise: nil)
        connectionClosed()
      }
      return
    }
    frameRequestOutstanding = true
    requestStartedAt = ProcessInfo.processInfo.systemUptime
    send(.requestFrame)
  }

  public func run() {
    lifetimeRetain = self
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    app.activate(ignoringOtherApps: true)
    app.run()
  }

  public func windowWillClose(_ notification: Notification) {
    shutdown()
    NSApplication.shared.terminate(nil)
  }

  public func windowDidResize(_ notification: Notification) {
    guard !isShuttingDown else { return }
    send(.viewport(currentViewport))
  }

  private func shutdown() {
    guard !isShuttingDown else { return }
    isShuttingDown = true
    connectionGeneration = UUID()
    reconnectTimer?.invalidate()
    reconnectTimer = nil
    banner.dismiss()

    frameRequestTimer?.invalidate()
    frameRequestTimer = nil
    view.onInputAvailable = nil
    view.onRemoteKey = nil
    clipboardGenerations.removeAll()
    view.delegate = nil
    window.delegate = nil

    let openChannel = channel
    channel = nil
    if let openChannel, openChannel.isActive {
      try? openChannel.close().wait()
    }
    try? group.syncShutdownGracefully()
    lifetimeRetain = nil
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  public func draw(in view: MTKView) {
    guard
      let drawable = view.currentDrawable,
      let descriptor = view.currentRenderPassDescriptor
    else { return }
    let viewport = currentViewport
    let overlay = banner.render(viewport: viewport)
    let commands = (latestFrame?.commands ?? []) + overlay.commands
    let renderStarted = ProcessInfo.processInfo.systemUptime
    do {
      guard
        let prepared = try displayRenderer.prepareFrame(
          DrawList(commands: commands), viewport: viewport,
          rasterScale: Point(
            x: Float(drawable.texture.width) / max(1, viewport.width),
            y: Float(drawable.texture.height) / max(1, viewport.height)),
          queue: queue, renderPass: descriptor)
      else {
        view.needsDisplay = true
        return
      }
      _ = prepared.submit(presenting: drawable) { [weak self] completion in
        guard let duration = completion.gpuDuration else { return }
        DispatchQueue.main.async {
          guard let self else { return }
          self.statistics.gpuTime += duration
          self.statistics.gpuFrames += 1
        }
      }
    } catch {
      view.needsDisplay = true
      return
    }
    statistics.draws += 1
    statistics.drawCalls += displayRenderer.lastDrawCallCount
    statistics.instances += displayRenderer.lastInstanceCount
    statistics.renderTime += ProcessInfo.processInfo.systemUptime - renderStarted
  }

  private var currentViewport: Size {
    Size(width: Float(view.bounds.width), height: Float(view.bounds.height))
  }

  private func sendPendingInput() {
    guard !isShuttingDown else { return }
    inputSequence &+= 1
    let input = view.frameInput()
    if banner.handleInput(input, viewport: currentViewport) { return }
    send(.input(sequence: inputSequence, state: input))
  }

  private func send(_ message: RemoteMessage) {
    guard !isShuttingDown, let channel, channel.isActive else { return }
    do {
      let bytes = try RemoteWire.encode(message)
      channel.writeAndFlush(bytes, promise: nil)
    } catch {
      print("Remote message encoding failed: \(error)")
    }
  }

  private func connectionClosed() {
    guard !isShuttingDown else { return }
    connectionGeneration = UUID()
    frameRequestTimer?.invalidate()
    frameRequestTimer = nil
    frameRequestOutstanding = false
    channel = nil
    clipboardGenerations.removeAll()
    if !awaitingReconnectFrame {
      awaitingReconnectFrame = true
      window.title = "\(connectedTitle) — reconnecting"
      banner.show("Connection lost. Reconnecting automatically…")
    }
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    guard !isShuttingDown, endpoint != nil, reconnectTimer == nil else { return }
    let timer = Timer(timeInterval: reconnectDelay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.reconnectTimer = nil
        self?.reconnect()
      }
    }
    reconnectDelay = min(reconnectDelay * 2, 10)
    reconnectTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func reconnect() {
    guard !isShuttingDown, let endpoint else { return }
    let generation = UUID()
    connectionGeneration = generation
    openConnection(host: endpoint.host, port: endpoint.port, generation: generation)
      .whenComplete { [weak self] result in
        DispatchQueue.main.async {
          guard let self, !self.isShuttingDown, self.connectionGeneration == generation else {
            if case .success(let channel) = result { channel.close(promise: nil) }
            return
          }
          switch result {
          case .success(let channel):
            guard channel.isActive else {
              self.connectionClosed()
              return
            }
            do {
              try self.activate(channel)
            } catch {
              channel.close(promise: nil)
              self.connectionClosed()
            }
          case .failure:
            self.connectionClosed()
          }
        }
      }
  }

  private func receive(_ message: RemoteMessage, byteCount: Int, decodeDuration: TimeInterval) {
    guard !isShuttingDown else { return }
    switch message {
    case .frame, .frameUnchanged:
      if frameRequestOutstanding {
        statistics.requestTime += ProcessInfo.processInfo.systemUptime - requestStartedAt
        statistics.replies += 1
      }
    default: break
    }
    let isFirstFrame = latestFrame == nil
    let acceptedFrame = frameState.receive(message)
    if case .frameUnchanged = message {
      statistics.bytes += byteCount
      statistics.reportIfNeeded()
      return
    }
    if case .clipboard(let request) = message {
      guard !request.isReply else { return }
      guard let generation = clipboardGenerations.consume(sequence: request.id) else {
        banner.show("Clipboard operation failed: the input gesture has expired. Please try again.")
        send(.clipboard(ClipboardTransfer(id: request.id, isReply: true, success: false)))
        return
      }
      let pasteboard = NSPasteboard.general
      var reply = ClipboardTransfer(id: request.id, isReply: true, success: false)
      if let text = request.text {
        if pasteboard.changeCount == generation {
          pasteboard.clearContents()
          reply.success = pasteboard.setString(text, forType: .string)
          if reply.success {
            clipboardGenerations.didWrite(
              sequence: request.id, from: generation, to: pasteboard.changeCount)
          }
        }
      } else if pasteboard.changeCount == generation {
        reply.text = pasteboard.string(forType: .string)
        reply.success = true
      }
      if !reply.success {
        banner.show("Clipboard operation failed: the clipboard changed or could not be written. Please try again.")
      }
      do {
        let result = try ClipboardReplyEncoder.encode(reply)
        if let notification = result.notification { banner.show(notification) }
        channel?.writeAndFlush(result.bytes, promise: nil)
      } catch {
        banner.show("Clipboard operation failed: could not encode the reply. Please try again.")
        send(.clipboard(ClipboardTransfer(id: request.id, isReply: true, success: false)))
      }
      return
    }
    guard case .frame(let id, _, _, let commands) = message else { return }
    guard acceptedFrame else { return }
    if isFirstFrame {
      print("Received remote frame \(id) with \(commands.count) draw commands")
    }
    if awaitingReconnectFrame {
      awaitingReconnectFrame = false
      reconnectDelay = 1
      window.title = connectedTitle
      banner.show("Reconnected to the remote daemon.", success: true, dismissAfter: 4)
    }
    statistics.frames += 1
    statistics.bytes += byteCount
    statistics.commands += commands.count
    statistics.decodeTime += decodeDuration
    statistics.reportIfNeeded()
    view.needsDisplay = true
  }
}

private final class RemoteClientHandler: ChannelInboundHandler, Sendable {
  typealias InboundIn = DecodedRemoteMessage
  private let onMessage: @Sendable (RemoteMessage, Int, TimeInterval) -> Void
  private let onInactive: @Sendable () -> Void

  init(
    onMessage: @escaping @Sendable (RemoteMessage, Int, TimeInterval) -> Void,
    onInactive: @escaping @Sendable () -> Void
  ) {
    self.onMessage = onMessage
    self.onInactive = onInactive
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let decoded = unwrapInboundIn(data)
    onMessage(decoded.message, decoded.byteCount, decoded.duration)
  }

  func channelInactive(context: ChannelHandlerContext) {
    onInactive()
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    print("Remote server error: \(error)")
    context.close(promise: nil)
  }
}

#endif
