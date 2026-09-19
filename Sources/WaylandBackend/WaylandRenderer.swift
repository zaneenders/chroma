import CEGL
import CWaylandClient
import CWaylandEGL
import CWaylandProtocols
import Chroma
import CoreFoundation
import Dispatch
import Foundation
import Glibc

@diagnose(
  StrictMemorySafety, as: ignored,
  reason:
    "Wayland/EGL handles and listener storage are managed by setup/cleanup on the main actor; C interop annotations are being migrated."
)
@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"
  private let frameProducer = FrameProducer()
  public var content: (any Block)? {
    didSet { frameProducer.reset() }
  }
  public var frameObserver: FrameObserver?
  public var onClose: (() -> Void)?

  package let interaction = Interaction()

  private var width: Int32
  private var height: Int32
  private var bufferScale: Int32 = 1
  private var running = true
  private var configured = false

  private var display: OpaquePointer?
  private var registry: OpaquePointer?
  private var compositor: OpaquePointer?
  private var wmBase: OpaquePointer?
  private var shm: OpaquePointer?
  private var seat: OpaquePointer?
  private var pointer: OpaquePointer?
  private var wlKeyboard: OpaquePointer?
  private let keyboard = WaylandKeyboard()
  private lazy var clipboard = WaylandClipboard(
    interaction: interaction, keyboard: keyboard,
    flush: { [weak self] in self?.flushWayland() },
    requestFrame: { [weak self] in self?.requestFrame() })
  private var surface: OpaquePointer?
  private var xdgSurface: OpaquePointer?
  private var toplevel: OpaquePointer?

  private let input = InputAccumulator()
  private let cursor = WaylandCursor()
  private var minimumRefreshRate: Double = 0
  private var displayReadSource: DispatchSourceRead?
  private var displayWriteSource: DispatchSourceWrite?
  private var refreshTimer: DispatchSourceTimer?
  private var keyboardRepeatTimer: DispatchSourceTimer?
  private var frameCallback: OpaquePointer?
  private var framePending = false
  private var dirty = false
  private var eventLoopError: Error?
  private var lastFrameTime: Double = 0
  private var smoothedFrameRate: Double = 0

  private var eglDisplay: EGLDisplay?
  private var eglContext: EGLContext?
  private var eglSurface: EGLSurface?
  private var eglWindow: OpaquePointer?

  private let openGL = OpenGLRenderer()

  private static var compositorInterface: wl_interface = unsafe wl_compositor_interface
  private static var wmBaseInterface: wl_interface = unsafe xdg_wm_base_interface
  private static var seatInterface: wl_interface = unsafe wl_seat_interface
  private static var shmInterface: wl_interface = unsafe wl_shm_interface
  public init(size: Size = Size(width: 800, height: 600)) {
    width = max(1, Int32(size.width))
    height = max(1, Int32(size.height))
    keyboard.onCopy = { [weak self] in self?.clipboard.copyToClipboard() }
    keyboard.onCut = { [weak self] in self?.clipboard.copyEditableSelectionToClipboard() ?? false }
    keyboard.onPaste = { [weak self] id in self?.clipboard.pasteFromClipboard(id: id) }
    keyboard.onSelectAll = { [weak self] in self?.selectAllOutsideEditor() ?? false }
  }

  package func setMinimumRefreshRate(_ refreshRate: Double) {
    minimumRefreshRate = refreshRate.isFinite ? max(0, refreshRate) : 0
  }

  package func setKeyBindings(_ bindings: KeyBindings) {
    keyboard.setKeyBindings(bindings)
  }

  public func run(title: String) throws {
    running = true
    eventLoopError = nil
    defer { cleanup() }
    try setUpWayland(title: title)
    try waitForInitialConfigure()
    guard running else { return }
    try setUpEGL()
    try openGL.setUp()

    interaction.onRedrawRequested = { [weak self] in
      self?.requestFrame()
    }
    startEventSources()
    requestFrame()

    while running {
      _ = RunLoop.main.run(mode: .default, before: .distantFuture)
    }
    if let eventLoopError { throw eventLoopError }
  }

  private func waitForInitialConfigure() throws {
    guard let display else { throw WaylandError("Wayland display is unavailable") }
    while running, !configured {
      guard unsafe wl_display_dispatch(display) != -1 else {
        throw WaylandError("display disconnected before initial configure")
      }
    }
  }

  private func startEventSources() {
    guard let display else { return }
    let fd = unsafe wl_display_get_fd(display)
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.displayBecameReadable() }
    }
    displayReadSource = source
    source.resume()
    updateRefreshTimer()
    updateKeyboardRepeatTimer()
    flushWayland()
  }

  private func displayBecameReadable() {
    guard running, let display else { return }
    guard unsafe wl_display_dispatch(display) != -1 else {
      failEventLoop(WaylandError("Wayland display dispatch failed"))
      return
    }
    updateKeyboardRepeatTimer()
    flushWayland()
  }

  private func flushWayland() {
    guard running, let display else { return }
    let result = unsafe wl_display_flush(display)
    if result >= 0 {
      displayWriteSource?.cancel()
      displayWriteSource = nil
      return
    }
    guard errno == EAGAIN else {
      failEventLoop(WaylandError("Wayland display flush failed"))
      return
    }
    guard displayWriteSource == nil else { return }
    let fd = unsafe wl_display_get_fd(display)
    let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.flushWayland() }
    }
    displayWriteSource = source
    source.resume()
  }

  private func updateRefreshTimer() {
    refreshTimer?.cancel()
    refreshTimer = nil
    guard running, minimumRefreshRate > 0 else { return }
    let interval = 1 / minimumRefreshRate
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.requestFrame() }
    }
    refreshTimer = timer
    timer.resume()
  }

  private func updateKeyboardRepeatTimer() {
    keyboardRepeatTimer?.cancel()
    keyboardRepeatTimer = nil
    guard running, let deadline = keyboard.repeatDeadline else { return }
    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + delay, leeway: .milliseconds(1))
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.keyboardRepeatTimerFired() }
    }
    keyboardRepeatTimer = timer
    timer.resume()
  }

  private func keyboardRepeatTimerFired() {
    keyboardRepeatTimer?.cancel()
    keyboardRepeatTimer = nil
    let repeated = keyboard.dispatchRepeats(
      interaction: interaction, editing: interaction.mode == .editing,
      editingSession: interaction.editingSessionGeneration,
      now: ProcessInfo.processInfo.systemUptime)
    if repeated { requestFrame() }
    updateKeyboardRepeatTimer()
  }

  private func requestFrame() {
    guard running, configured, eglSurface != nil else { return }
    dirty = true
    renderIfPossible()
  }

  private func renderIfPossible() {
    guard dirty, !framePending, running else { return }
    guard let surface else { return }
    dirty = false
    guard let callback = unsafe wl_surface_frame(surface) else {
      failEventLoop(WaylandError("could not create Wayland frame callback"))
      return
    }
    frameCallback = callback
    framePending = true
    unsafe wl_callback_add_listener(
      callback, &Self.frameListener, Unmanaged.passUnretained(self).toOpaque())
    drawFrame()
    flushWayland()
  }

  private static var frameListener = unsafe wl_callback_listener(
    done: { data, callback, _ in
      nonisolated(unsafe) let callback = callback
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        if let callback { unsafe wl_callback_destroy(callback) }
        if renderer.frameCallback == callback { renderer.frameCallback = nil }
        renderer.framePending = false
        renderer.renderIfPossible()
      }
    }
  )

  private func failEventLoop(_ error: Error) {
    guard running else { return }
    eventLoopError = error
    stopEventLoop()
  }

  private func stopEventLoop() {
    running = false
    CFRunLoopStop(CFRunLoopGetMain())
  }

  private func setUpWayland(title: String) throws {
    display = unsafe wl_display_connect(nil)
    guard let display else { throw WaylandError("could not connect to WAYLAND_DISPLAY") }

    registry = unsafe wl_display_get_registry(display)
    guard let registry else { throw WaylandError("could not get Wayland registry") }
    unsafe wl_registry_add_listener(registry, &Self.registryListener, Unmanaged.passUnretained(self).toOpaque())
    guard unsafe wl_display_roundtrip(display) >= 0 else { throw WaylandError("registry roundtrip failed") }
    guard let compositor, let wmBase else {
      throw WaylandError("compositor does not provide wl_compositor and xdg_wm_base")
    }

    surface = unsafe wl_compositor_create_surface(compositor)
    guard let surface else { throw WaylandError("could not create wl_surface") }
    unsafe wl_surface_add_listener(
      surface, &Self.surfaceListener, Unmanaged.passUnretained(self).toOpaque())
    xdgSurface = unsafe xdg_wm_base_get_xdg_surface(wmBase, surface)
    guard let xdgSurface else { throw WaylandError("could not create xdg_surface") }
    unsafe xdg_surface_add_listener(xdgSurface, &Self.xdgSurfaceListener, Unmanaged.passUnretained(self).toOpaque())

    toplevel = unsafe xdg_surface_get_toplevel(xdgSurface)
    guard let toplevel else { throw WaylandError("could not create xdg_toplevel") }
    unsafe xdg_toplevel_add_listener(toplevel, &Self.toplevelListener, Unmanaged.passUnretained(self).toOpaque())
    title.withCString { unsafe xdg_toplevel_set_title(toplevel, $0) }
    unsafe wl_surface_commit(surface)
  }

  private func selectAllOutsideEditor() -> Bool {
    guard interaction.mode != .editing else { return false }
    interaction.selectAll(at: input.pointerPositionSnapshot)
    requestFrame()
    return true
  }

  private static var registryListener = unsafe wl_registry_listener(
    global: { data, registry, name, interface, version in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let interface = interface
      nonisolated(unsafe) let registry = registry
      MainActor.assumeIsolated {
        guard let data, let registry, let interface else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        switch unsafe String(cString: interface) {
        case "wl_compositor":
          renderer.compositor = unsafe OpaquePointer(
            wl_registry_bind(registry, name, &compositorInterface, min(version, 6)))
          renderer.setUpCursorIfReady()
        case "xdg_wm_base":
          renderer.wmBase = unsafe OpaquePointer(
            wl_registry_bind(registry, name, &wmBaseInterface, min(version, 2)))
          if let wmBase = renderer.wmBase {
            unsafe xdg_wm_base_add_listener(
              wmBase, &wmBaseListener, Unmanaged.passUnretained(renderer).toOpaque())
          }
        case "wl_seat":
          renderer.seat = unsafe OpaquePointer(
            wl_registry_bind(registry, name, &seatInterface, min(version, 5)))
          if let seat = renderer.seat {
            unsafe wl_seat_add_listener(
              seat, &seatListener, Unmanaged.passUnretained(renderer).toOpaque())
          }
          renderer.clipboard.setUp(seat: renderer.seat)
        case "wl_data_device_manager":
          renderer.clipboard.bind(registry: registry, name: name, version: version)
          renderer.clipboard.setUp(seat: renderer.seat)
        case "wl_shm":
          renderer.shm = unsafe OpaquePointer(
            wl_registry_bind(registry, name, &shmInterface, min(version, 1)))
          renderer.setUpCursorIfReady()
        default: break
        }
      }
    },
    global_remove: { _, _, _ in }
  )

  private static var wmBaseListener = unsafe xdg_wm_base_listener(
    ping: { _, base, serial in unsafe xdg_wm_base_pong(base, serial) }
  )

  private static var seatListener = unsafe wl_seat_listener(
    capabilities: { data, seat, capabilities in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let seat = seat
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        let hasPointer = (capabilities & WL_SEAT_CAPABILITY_POINTER.rawValue) != 0
        if hasPointer, renderer.pointer == nil, let seat {
          renderer.pointer = unsafe wl_seat_get_pointer(seat)
          if let pointer = renderer.pointer {
            unsafe wl_pointer_add_listener(
              pointer, &pointerListener, Unmanaged.passUnretained(renderer).toOpaque())
          }
        } else if !hasPointer, let pointer = renderer.pointer {
          unsafe wl_pointer_destroy(pointer)
          renderer.pointer = nil
        }
        let hasKeyboard = (capabilities & WL_SEAT_CAPABILITY_KEYBOARD.rawValue) != 0
        if hasKeyboard, renderer.wlKeyboard == nil, let seat {
          renderer.wlKeyboard = unsafe wl_seat_get_keyboard(seat)
          if let keyboard = renderer.wlKeyboard {
            unsafe wl_keyboard_add_listener(
              keyboard, &keyboardListener, Unmanaged.passUnretained(renderer).toOpaque())
          }
        } else if !hasKeyboard, let keyboard = renderer.wlKeyboard {
          renderer.keyboard.focusLost()
          unsafe wl_keyboard_destroy(keyboard)
          renderer.wlKeyboard = nil
        }
      }
    },
    name: { _, _, _ in }
  )

  private static var keyboardListener = unsafe wl_keyboard_listener(
    keymap: { data, _, format, fd, size in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data, format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1.rawValue else {
          if fd >= 0 { close(fd) }
          return
        }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.keyboard.installKeymap(fd: fd, size: size)
      }
    },
    enter: { data, _, serial, _, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.clipboard.latestInputSerial = serial
      }
    },
    leave: { data, _, _, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.keyboard.focusLost()
      }
    },
    key: { data, _, serial, _, key, state in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.clipboard.latestInputSerial = serial
        if state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue {
          renderer.keyboard.keyPressed(
            key,
            interaction: renderer.interaction,
            editing: renderer.interaction.mode == .editing,
            editingSession: renderer.interaction.editingSessionGeneration,
            now: ProcessInfo.processInfo.systemUptime
          )
          renderer.requestFrame()
        } else {
          renderer.keyboard.keyReleased(key)
        }
      }
    },
    modifiers: { data, _, _, depressed, latched, locked, group in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.keyboard.updateModifiers(
          depressed: depressed, latched: latched, locked: locked, group: group)
      }
    },
    repeat_info: { data, _, rate, delay in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.keyboard.updateRepeatInfo(rate: rate, delay: delay)
      }
    }
  )

  private static let pointerEnter:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, OpaquePointer?, Int32, Int32) -> Void = {
      data, pointer, serial, eventSurface, surfaceX, surfaceY in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let eventSurface = eventSurface
      nonisolated(unsafe) let pointer = pointer
      MainActor.assumeIsolated {
        guard let data, let eventSurface else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        guard eventSurface == renderer.surface else { return }
        if let pointer { renderer.cursor.apply(pointer: pointer, serial: serial) }
        renderer.input.pointerEntered(
          x: fixedToFloat(surfaceX), y: fixedToFloat(surfaceY))
        renderer.requestFrame()
      }
    }

  private static let pointerLeave:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, OpaquePointer?) -> Void = {
      data, _, _, eventSurface in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let eventSurface = eventSurface
      MainActor.assumeIsolated {
        guard let data, let eventSurface else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        guard eventSurface == renderer.surface else { return }
        renderer.input.pointerLeft()
        renderer.requestFrame()
      }
    }

  private static let pointerMotion:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, Int32, Int32) -> Void = {
      data, _, _, surfaceX, surfaceY in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.input.pointerMoved(
          x: fixedToFloat(surfaceX), y: fixedToFloat(surfaceY))
        renderer.requestFrame()
      }
    }

  private static let pointerButton:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, UInt32, UInt32, UInt32) -> Void = {
      data, _, serial, _, button, state in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data, button == btnLeft else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.clipboard.latestInputSerial = serial
        switch state {
        case WL_POINTER_BUTTON_STATE_PRESSED.rawValue:
          renderer.input.pointerPressed()
        case WL_POINTER_BUTTON_STATE_RELEASED.rawValue:
          renderer.input.pointerReleased()
        default: break
        }
        renderer.requestFrame()
      }
    }

  private static let pointerAxis:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, UInt32, Int32) -> Void = {
      data, _, time, axis, value in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        let delta = -fixedToFloat(value)
        switch axis {
        case WL_POINTER_AXIS_HORIZONTAL_SCROLL.rawValue:
          renderer.input.scrollBy(x: delta, y: 0, time: time)
        case WL_POINTER_AXIS_VERTICAL_SCROLL.rawValue:
          renderer.input.scrollBy(x: 0, y: delta, time: time)
        default: break
        }
        renderer.requestFrame()
      }
    }

  private static var pointerListener = unsafe wl_pointer_listener(
    enter: pointerEnter,
    leave: pointerLeave,
    motion: pointerMotion,
    button: pointerButton,
    axis: pointerAxis,
    frame: { _, _ in },
    axis_source: { data, _, source in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.input.scrollSource(isFinger: source == WL_POINTER_AXIS_SOURCE_FINGER.rawValue)
      }
    },
    axis_stop: { data, _, time, axis in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.input.stopScroll(
          horizontal: axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL.rawValue, time: time)
        renderer.requestFrame()
      }
    },
    axis_discrete: { _, _, _, _ in },
    axis_value120: { _, _, _, _ in },
    axis_relative_direction: { _, _, _, _ in },
    warp: { _, _, _, _ in }
  )

  private static var surfaceListener = unsafe wl_surface_listener(
    enter: { _, _, _ in },
    leave: { _, _, _ in },
    preferred_buffer_scale: { data, surface, factor in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let surface = surface
      MainActor.assumeIsolated {
        guard let data, let surface, factor > 0 else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        guard factor != renderer.bufferScale else { return }
        renderer.bufferScale = factor
        unsafe wl_surface_set_buffer_scale(surface, factor)
        renderer.resizeEGLWindow()
        renderer.requestFrame()
      }
    },
    preferred_buffer_transform: { _, _, _ in }
  )

  private static var xdgSurfaceListener = unsafe xdg_surface_listener(
    configure: { data, xdgSurface, serial in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let xdgSurface = xdgSurface
      MainActor.assumeIsolated {
        unsafe xdg_surface_ack_configure(xdgSurface, serial)
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.configured = true
        renderer.requestFrame()
      }
    }
  )

  private static let configureCallback:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, Int32, Int32, UnsafeMutablePointer<wl_array>?) -> Void = {
      data, _, width, height, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data, width > 0, height > 0 else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        renderer.width = width
        renderer.height = height
        renderer.resizeEGLWindow()
        renderer.requestFrame()
      }
    }

  private func resizeEGLWindow() {
    guard let eglWindow else { return }
    unsafe wl_egl_window_resize(
      eglWindow, width * bufferScale, height * bufferScale, 0, 0)
  }

  private static var toplevelListener = unsafe xdg_toplevel_listener(
    configure: configureCallback,
    close: { data, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
        guard renderer.running else { return }
        renderer.onClose?()
        renderer.stopEventLoop()
      }
    },
    configure_bounds: { _, _, _, _ in },
    wm_capabilities: { _, _, _ in }
  )

  private func setUpEGL() throws {
    guard let display, let surface else { throw WaylandError("Wayland surface is unavailable") }
    eglDisplay = unsafe eglGetDisplay(EGLNativeDisplayType(display))
    guard eglDisplay != nil, unsafe eglInitialize(eglDisplay, nil, nil) == EGL_TRUE else {
      throw WaylandError("eglInitialize failed")
    }
    guard eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) == EGL_TRUE else {
      throw WaylandError("eglBindAPI(OpenGL ES) failed")
    }

    var config: EGLConfig?
    var count: EGLint = 0
    let attributes: [EGLint] = [
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
      EGL_NONE,
    ]
    attributes.withUnsafeBufferPointer {
      _ = unsafe eglChooseConfig(eglDisplay, $0.baseAddress, &config, 1, &count)
    }
    guard count > 0, config != nil else { throw WaylandError("no EGL ES3 window config") }

    let contextAttributes: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE]
    eglContext = contextAttributes.withUnsafeBufferPointer {
      unsafe eglCreateContext(eglDisplay, config, nil, $0.baseAddress)
    }
    guard eglContext != nil else { throw WaylandError("eglCreateContext failed") }

    unsafe wl_surface_set_buffer_scale(surface, bufferScale)
    eglWindow = unsafe wl_egl_window_create(
      surface, width * bufferScale, height * bufferScale)
    guard let eglWindow else { throw WaylandError("wl_egl_window_create failed") }
    eglSurface = unsafe eglCreateWindowSurface(
      eglDisplay, config, EGLNativeWindowType(bitPattern: eglWindow), nil)
    guard eglSurface != nil else { throw WaylandError("eglCreateWindowSurface failed") }
    guard unsafe eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext) == EGL_TRUE else {
      throw WaylandError("eglMakeCurrent failed")
    }
    _ = unsafe eglSwapInterval(eglDisplay, 1)
  }

  private func drawFrame() {
    guard eglDisplay != nil, eglSurface != nil else { return }
    openGL.beginFrame(width: width, height: height, bufferScale: bufferScale)

    updateFrameRate()
    input.drainKeyboard(keyboard, editingSession: interaction.editingSessionGeneration)
    let viewport = Size(width: Float(width), height: Float(height))
    let drawList = frameProducer.render(
      content: content, viewport: viewport, input: input.frameInput(), context: context,
      onChange: { [weak self] in self?.requestFrame() })
    frameObserver?(
      FrameObservation(
        drawList: drawList, viewport: viewport, rasterScale: Point(x: Float(bufferScale), y: Float(bufferScale))))
    _ = interaction.consumeRedrawRequest()
    openGL.render(drawList, viewport: viewport, bufferScale: bufferScale)
    _ = unsafe eglSwapBuffers(eglDisplay, eglSurface)
    if frameProducer.needsAnimationFrame || input.hasScrollMomentum { dirty = true }
  }

  private func updateFrameRate() {
    let now = ProcessInfo.processInfo.systemUptime
    defer { lastFrameTime = now }
    guard lastFrameTime > 0 else { return }
    let delta = now - lastFrameTime
    guard delta > 0 else { return }
    let instant = 1 / delta
    smoothedFrameRate = smoothedFrameRate == 0 ? instant : smoothedFrameRate * 0.9 + instant * 0.1
    interaction.frameRate = smoothedFrameRate
  }

  private func setUpCursorIfReady() {
    guard let compositor, let shm else { return }
    cursor.setUp(compositor: compositor, shm: shm)
  }

  private func cleanup() {
    frameProducer.reset()
    interaction.onRedrawRequested = nil
    refreshTimer?.cancel()
    keyboardRepeatTimer?.cancel()
    displayReadSource?.cancel()
    displayWriteSource?.cancel()
    refreshTimer = nil
    keyboardRepeatTimer = nil
    displayReadSource = nil
    displayWriteSource = nil
    if let frameCallback { unsafe wl_callback_destroy(frameCallback) }
    frameCallback = nil
    framePending = false
    dirty = false

    openGL.cleanup()

    if let eglDisplay {
      _ = unsafe eglMakeCurrent(eglDisplay, nil, nil, nil)
      if let eglSurface { _ = unsafe eglDestroySurface(eglDisplay, eglSurface) }
      if let eglContext { _ = unsafe eglDestroyContext(eglDisplay, eglContext) }
      _ = unsafe eglTerminate(eglDisplay)
    }
    if let eglWindow { unsafe wl_egl_window_destroy(eglWindow) }
    eglSurface = nil
    eglContext = nil
    eglDisplay = nil
    self.eglWindow = nil

    cursor.cleanup()
    keyboard.cleanup()
    clipboard.cleanup()
    if let pointer { unsafe wl_pointer_destroy(pointer) }
    if let wlKeyboard { unsafe wl_keyboard_destroy(wlKeyboard) }
    if let seat { unsafe wl_seat_destroy(seat) }
    if let shm { unsafe wl_shm_destroy(shm) }
    if let toplevel { unsafe xdg_toplevel_destroy(toplevel) }
    if let xdgSurface { unsafe xdg_surface_destroy(xdgSurface) }
    if let surface { unsafe wl_surface_destroy(surface) }
    if let wmBase { unsafe xdg_wm_base_destroy(wmBase) }
    if let compositor { unsafe wl_compositor_destroy(compositor) }
    if let registry { unsafe wl_registry_destroy(registry) }
    if let display { unsafe wl_display_disconnect(display) }
    pointer = nil
    wlKeyboard = nil
    seat = nil
    shm = nil
    toplevel = nil
    xdgSurface = nil
    surface = nil
    wmBase = nil
    compositor = nil
    registry = nil
    display = nil
    configured = false
  }
}

private struct WaylandError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

private func fixedToFloat(_ value: Int32) -> Float {
  Float(value) / 256
}

private let btnLeft: UInt32 = 0x110
