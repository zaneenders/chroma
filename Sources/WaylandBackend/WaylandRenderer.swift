#if WAYLAND_BACKEND

import CEGL
import CGLES3
import Chroma
import CWaylandClient
import CWaylandEGL
import CWaylandProtocols
import Foundation
import Glibc

/// A Wayland window backed by EGL and OpenGL ES 3.
///
/// Like `MetalRenderer`, this type owns the platform surface and consumes only
/// backend-neutral `DrawList` commands produced by `BlockEngine`.
@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"
  public var content: (any Block)?
  public var onClose: (() -> Void)?

  package let interaction = Interaction()

  // xdg-shell configures surfaces in logical coordinates. The EGL window and
  // GL viewport use buffer pixels so HiDPI outputs are rendered at native
  // resolution instead of being upscaled by the compositor.
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
  private var surface: OpaquePointer?
  private var xdgSurface: OpaquePointer?
  private var toplevel: OpaquePointer?

  private let input = InputAccumulator()
  private let cursor = WaylandCursor()
  private var minimumRefreshRate: Double = 0
  private var lastFrameTime: Double = 0
  private var smoothedFrameRate: Double = 0

  private var eglDisplay: EGLDisplay?
  private var eglContext: EGLContext?
  private var eglSurface: EGLSurface?
  private var eglWindow: OpaquePointer?

  private var program: GLuint = 0
  private var vao: GLuint = 0
  private var quadVBO: GLuint = 0
  private var instanceVBO: GLuint = 0
  private var whiteTexture: GLuint = 0
  private var fontTexture: GLuint = 0
  private var fontAtlas: FontAtlas?
  private var resolutionUniform: GLint = -1

  private static var compositorInterface: wl_interface = unsafe wl_compositor_interface
  private static var wmBaseInterface: wl_interface = unsafe xdg_wm_base_interface
  private static var seatInterface: wl_interface = unsafe wl_seat_interface
  private static var shmInterface: wl_interface = unsafe wl_shm_interface

  public init(size: Size = Size(width: 800, height: 600)) {
    width = max(1, Int32(size.width))
    height = max(1, Int32(size.height))
  }

  package func setMinimumRefreshRate(_ refreshRate: Double) {
    minimumRefreshRate = refreshRate.isFinite ? max(0, refreshRate) : 0
  }

  package func setKeyBindings(_ bindings: KeyBindings) {
    keyboard.setKeyBindings(bindings)
  }

  public func run(title: String) throws {
    defer { cleanup() }
    try setUpWayland(title: title)
    try waitForInitialConfigure()
    guard running else { return }
    try setUpEGL()
    try setUpGL()
    drawFrame()
    try runEventLoop()
  }

  private func waitForInitialConfigure() throws {
    guard let display else { throw WaylandError("Wayland display is unavailable") }
    while running, !configured {
      guard unsafe wl_display_dispatch(display) != -1 else {
        throw WaylandError("display disconnected before initial configure")
      }
    }
  }

  private func runEventLoop() throws {
    guard let display else { throw WaylandError("Wayland display is unavailable") }
    let displayFD = unsafe wl_display_get_fd(display)
    let frameInterval = minimumRefreshRate > 0 ? 1 / minimumRefreshRate : nil
    var nextFrameTime = frameInterval.map { ProcessInfo.processInfo.systemUptime + $0 }

    while running {
      // Unlike AppKit, the native Wayland loop does not run Foundation's main
      // run loop for us. Swift's MainActor jobs use that run loop on Linux, so
      // give queued Tasks a chance to advance before blocking in poll. Without
      // this, UI actions can run synchronously but their Task bodies (history
      // discovery, session bootstrap, streaming updates) never start.
      _ = RunLoop.main.run(mode: .default, before: Date())

      while unsafe wl_display_prepare_read(display) != 0 {
        guard unsafe wl_display_dispatch_pending(display) != -1 else {
          throw WaylandError("Wayland display dispatch failed")
        }
        guard running else { return }
      }

      let flushResult = unsafe wl_display_flush(display)
      let wantsWrite = flushResult == -1 && errno == EAGAIN
      guard flushResult != -1 || wantsWrite else {
        unsafe wl_display_cancel_read(display)
        throw WaylandError("Wayland display flush failed")
      }

      let timeout = pollTimeout(until: earliestDeadline(nextFrameTime, keyboard.repeatDeadline))
      let events = Int16(POLLIN) | (wantsWrite ? Int16(POLLOUT) : 0)
      var descriptor = pollfd(fd: displayFD, events: events, revents: 0)
      let result = unsafe poll(&descriptor, 1, timeout)
      if result < 0 {
        unsafe wl_display_cancel_read(display)
        if errno == EINTR { continue }
        throw WaylandError("polling the Wayland display failed")
      }

      if result > 0, descriptor.revents & Int16(POLLIN) != 0 {
        guard unsafe wl_display_read_events(display) != -1 else {
          throw WaylandError("reading Wayland events failed")
        }
        guard unsafe wl_display_dispatch_pending(display) != -1 else {
          throw WaylandError("Wayland display dispatch failed")
        }
        if running { drawFrame() }
      } else {
        unsafe wl_display_cancel_read(display)
        let failures = Int16(POLLERR | POLLHUP | POLLNVAL)
        if result > 0, descriptor.revents & failures != 0 {
          throw WaylandError("Wayland display became unavailable")
        }
        if wantsWrite, descriptor.revents & Int16(POLLOUT) != 0 {
          guard unsafe wl_display_flush(display) != -1 || errno == EAGAIN else {
            throw WaylandError("Wayland display flush failed")
          }
        }
      }

      let now = ProcessInfo.processInfo.systemUptime
      let repeated = keyboard.dispatchRepeats(editing: interaction.mode == .editing, now: now)
      var drewFrame = false
      if repeated, running {
        drawFrame()
        drewFrame = true
      }

      if let interval = frameInterval, now >= (nextFrameTime ?? 0) {
        if running, !drewFrame { drawFrame() }
        nextFrameTime = now + interval
      }
    }
  }

  private func earliestDeadline(_ first: Double?, _ second: Double?) -> Double? {
    switch (first, second) {
    case (.some(let first), .some(let second)): min(first, second)
    case (.some(let first), .none): first
    case (.none, .some(let second)): second
    case (.none, .none): nil
    }
  }

  private func pollTimeout(until deadline: Double?) -> Int32 {
    guard let deadline else { return -1 }
    let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
    return Int32(min(remaining * 1_000, Double(Int32.max)).rounded(.up))
  }

  // MARK: Wayland

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

  private static var registryListener = unsafe wl_registry_listener(
    global: { data, registry, name, interface, version in
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
      case "wl_shm":
        renderer.shm = unsafe OpaquePointer(
          wl_registry_bind(registry, name, &shmInterface, min(version, 1)))
        renderer.setUpCursorIfReady()
      default: break
      }
    },
    global_remove: { _, _, _ in }
  )

  private static var wmBaseListener = unsafe xdg_wm_base_listener(
    ping: { _, base, serial in unsafe xdg_wm_base_pong(base, serial) }
  )

  private static var seatListener = unsafe wl_seat_listener(
    capabilities: { data, seat, capabilities in
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
    },
    name: { _, _, _ in }
  )

  private static var keyboardListener = unsafe wl_keyboard_listener(
    keymap: { data, _, format, fd, size in
      guard let data, format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1.rawValue else {
        if fd >= 0 { close(fd) }
        return
      }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.keyboard.installKeymap(fd: fd, size: size)
    },
    enter: { _, _, _, _, _ in },
    leave: { data, _, _, _ in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.keyboard.focusLost()
    },
    key: { data, _, _, _, key, state in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      if state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue {
        renderer.keyboard.keyPressed(
          key,
          editing: renderer.interaction.mode == .editing,
          now: ProcessInfo.processInfo.systemUptime
        )
      } else {
        renderer.keyboard.keyReleased(key)
      }
    },
    modifiers: { data, _, _, depressed, latched, locked, group in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.keyboard.updateModifiers(
        depressed: depressed, latched: latched, locked: locked, group: group)
    },
    repeat_info: { data, _, rate, delay in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.keyboard.updateRepeatInfo(rate: rate, delay: delay)
    }
  )

  private static let pointerEnter:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, OpaquePointer?, Int32, Int32) -> Void = {
      data, pointer, serial, eventSurface, surfaceX, surfaceY in
      guard let data, let eventSurface else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      guard eventSurface == renderer.surface else { return }
      if let pointer { renderer.cursor.apply(pointer: pointer, serial: serial) }
      renderer.input.pointerEntered(
        x: fixedToFloat(surfaceX), y: fixedToFloat(surfaceY))
    }

  private static let pointerLeave:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, OpaquePointer?) -> Void = {
      data, _, _, eventSurface in
      guard let data, let eventSurface else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      guard eventSurface == renderer.surface else { return }
      renderer.input.pointerLeft()
    }

  private static let pointerMotion:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, Int32, Int32) -> Void = {
      data, _, _, surfaceX, surfaceY in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.input.pointerMoved(
        x: fixedToFloat(surfaceX), y: fixedToFloat(surfaceY))
    }

  private static let pointerButton:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, UInt32, UInt32, UInt32) -> Void = {
      data, _, _, _, button, state in
      guard let data, button == btnLeft else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      switch state {
      case WL_POINTER_BUTTON_STATE_PRESSED.rawValue:
        renderer.input.pointerPressed()
      case WL_POINTER_BUTTON_STATE_RELEASED.rawValue:
        renderer.input.pointerReleased()
      default: break
      }
    }

  private static let pointerAxis:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, UInt32, Int32) -> Void = {
      data, _, _, axis, value in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      // Wayland axis values describe content movement, while Chroma's scroll
      // delta follows AppKit's gesture direction. Flip the sign at the backend
      // boundary so wheel and touchpad scrolling move the viewport naturally.
      let delta = -fixedToFloat(value)
      switch axis {
      case WL_POINTER_AXIS_HORIZONTAL_SCROLL.rawValue:
        renderer.input.scrollBy(x: delta, y: 0)
      case WL_POINTER_AXIS_VERTICAL_SCROLL.rawValue:
        renderer.input.scrollBy(x: 0, y: delta)
      default: break
      }
    }

  private static var pointerListener = unsafe wl_pointer_listener(
    enter: pointerEnter,
    leave: pointerLeave,
    motion: pointerMotion,
    button: pointerButton,
    axis: pointerAxis,
    frame: { _, _ in },
    axis_source: { _, _, _ in },
    axis_stop: { _, _, _, _ in },
    axis_discrete: { _, _, _, _ in },
    axis_value120: { _, _, _, _ in },
    axis_relative_direction: { _, _, _, _ in }
  )

  private static var surfaceListener = unsafe wl_surface_listener(
    enter: { _, _, _ in },
    leave: { _, _, _ in },
    preferred_buffer_scale: { data, surface, factor in
      guard let data, let surface, factor > 0 else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      guard factor != renderer.bufferScale else { return }
      renderer.bufferScale = factor
      unsafe wl_surface_set_buffer_scale(surface, factor)
      renderer.resizeEGLWindow()
    },
    preferred_buffer_transform: { _, _, _ in }
  )

  private static var xdgSurfaceListener = unsafe xdg_surface_listener(
    configure: { data, xdgSurface, serial in
      unsafe xdg_surface_ack_configure(xdgSurface, serial)
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.configured = true
    }
  )

  private static let configureCallback:
    @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, Int32, Int32, UnsafeMutablePointer<wl_array>?) -> Void = {
      data, _, width, height, _ in
      guard let data, width > 0, height > 0 else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      renderer.width = width
      renderer.height = height
      renderer.resizeEGLWindow()
    }

  private func resizeEGLWindow() {
    guard let eglWindow else { return }
    unsafe wl_egl_window_resize(
      eglWindow, width * bufferScale, height * bufferScale, 0, 0)
  }

  private static var toplevelListener = unsafe xdg_toplevel_listener(
    configure: configureCallback,
    close: { data, _ in
      guard let data else { return }
      let renderer = unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue()
      guard renderer.running else { return }
      renderer.running = false
      renderer.onClose?()
    },
    configure_bounds: { _, _, _, _ in },
    wm_capabilities: { _, _, _ in }
  )

  // MARK: EGL / GLES

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
    var attributes: [EGLint] = [
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
      EGL_NONE,
    ]
    attributes.withUnsafeMutableBufferPointer {
      _ = unsafe eglChooseConfig(eglDisplay, $0.baseAddress, &config, 1, &count)
    }
    guard count > 0, config != nil else { throw WaylandError("no EGL ES3 window config") }

    var contextAttributes: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE]
    eglContext = contextAttributes.withUnsafeMutableBufferPointer {
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

  private func compileShader(_ type: GLenum, source: String, stage: String) throws -> GLuint {
    let shader = glCreateShader(type)
    source.withCString { sourcePointer in
      var pointer: UnsafePointer<GLchar>? = unsafe UnsafePointer(sourcePointer)
      var length = GLint(source.utf8.count)
      unsafe glShaderSource(shader, 1, &pointer, &length)
    }
    glCompileShader(shader)
    var succeeded: GLint = 0
    unsafe glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &succeeded)
    guard succeeded != 0 else {
      var length: GLint = 0
      unsafe glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &length)
      var log = [GLchar](repeating: 0, count: max(1, Int(length)))
      unsafe glGetShaderInfoLog(shader, length, nil, &log)
      let message = String(
        decoding: log.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
      )
      glDeleteShader(shader)
      throw BackendError.initializationFailed(
        backend: "Wayland",
        stage: stage,
        reason: message.isEmpty ? "shader compilation failed without a driver log" : message
      )
    }
    return shader
  }

  private func setUpGL() throws {
    let vertex = try compileShader(
      GLenum(GL_VERTEX_SHADER), source: vertexShader, stage: "vertex shader")
    let fragment: GLuint
    do {
      fragment = try compileShader(
        GLenum(GL_FRAGMENT_SHADER), source: fragmentShader, stage: "fragment shader")
    } catch {
      glDeleteShader(vertex)
      throw error
    }
    program = glCreateProgram()
    glAttachShader(program, vertex)
    glAttachShader(program, fragment)
    glLinkProgram(program)
    glDeleteShader(vertex)
    glDeleteShader(fragment)

    var linked: GLint = 0
    unsafe glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linked)
    guard linked != 0 else {
      var length: GLint = 0
      unsafe glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &length)
      var log = [GLchar](repeating: 0, count: max(1, Int(length)))
      unsafe glGetProgramInfoLog(program, length, nil, &log)
      let message = String(
        decoding: log.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
      )
      glDeleteProgram(program)
      program = 0
      throw BackendError.initializationFailed(
        backend: "Wayland",
        stage: "shader program",
        reason: message.isEmpty ? "linking failed without a driver log" : message
      )
    }

    let corners: [Float] = [-1, -1, 1, -1, -1, 1, 1, 1]
    unsafe glGenVertexArrays(1, &vao)
    glBindVertexArray(vao)
    unsafe glGenBuffers(1, &quadVBO)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), quadVBO)
    corners.withUnsafeBytes {
      unsafe glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count, $0.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 8, nil)

    unsafe glGenBuffers(1, &instanceVBO)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), instanceVBO)
    glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<GLQuad>.stride, nil, GLenum(GL_DYNAMIC_DRAW))
    let stride = GLsizei(MemoryLayout<GLQuad>.stride)
    let offsets = [0, 8, 16, 24, 32]
    let sizes: [GLint] = [2, 2, 2, 2, 4]
    for index in 0..<5 {
      let attribute = GLuint(index + 1)
      glEnableVertexAttribArray(attribute)
      unsafe glVertexAttribPointer(
        attribute, sizes[index], GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
        UnsafeRawPointer(bitPattern: offsets[index]))
      glVertexAttribDivisor(attribute, 1)
    }

    whiteTexture = makeTexture(width: 1, height: 1, pixels: [255, 255, 255, 255])
    makeFontTexture()
    resolutionUniform = unsafe glGetUniformLocation(program, "uResolution")
    glUseProgram(program)
    glUniform1i(unsafe glGetUniformLocation(program, "uTexture"), 0)
    glEnable(GLenum(GL_BLEND))
    glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
  }

  private func makeTexture(
    width: Int,
    height: Int,
    pixels: [UInt8],
    filter: GLint = GL_NEAREST
  ) -> GLuint {
    var texture: GLuint = 0
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    pixels.withUnsafeBytes {
      unsafe glTexImage2D(
        GLenum(GL_TEXTURE_2D), 0, GLint(GL_RGBA), GLsizei(width), GLsizei(height), 0,
        GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
    }
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), filter)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), filter)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    return texture
  }

  private func makeFontTexture() {
    let atlas = FontAtlas()
    fontAtlas = atlas

    var texture: GLuint = 0
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    for (level, mip) in atlas.mipLevels.enumerated() {
      mip.pixels.withUnsafeBytes {
        unsafe glTexImage2D(
          GLenum(GL_TEXTURE_2D), GLint(level), GLint(GL_RED), GLsizei(mip.width),
          GLsizei(mip.height), 0, GLenum(GL_RED), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
      }
    }
    glTexParameteri(
      GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    fontTexture = texture
  }

  // MARK: DrawList consumption

  private func drawFrame() {
    guard eglDisplay != nil, eglSurface != nil else { return }
    glViewport(0, 0, width * bufferScale, height * bufferScale)
    glClearColor(0.1, 0.1, 0.2, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glUseProgram(program)
    // Geometry stays in logical surface coordinates; the larger viewport gives
    // each logical unit bufferScale pixels without changing app layout.
    glUniform2f(resolutionUniform, Float(width), Float(height))
    glBindVertexArray(vao)

    // Pointer input is accumulated from the wl_pointer listener and drained
    // once per frame, matching the Metal backend's event coalescing.
    updateFrameRate()
    input.drainKeyboard(keyboard)
    interaction.beginFrame(input: input.frameInput())

    let viewport = Size(width: Float(width), height: Float(height))
    var drawList = DrawList()
    if let content {
      BlockEngine.draw(
        content,
        into: &drawList,
        in: Rect(origin: .zero, size: viewport),
        context: context
      )
    }
    interaction.endFrame()
    render(drawList, viewport: viewport)
    _ = unsafe eglSwapBuffers(eglDisplay, eglSurface)
  }

  private func render(_ drawList: DrawList, viewport: Size) {
    var clips: [Rect] = []
    for command in drawList.commands {
      switch command {
      case .fillRect(let rect, let color):
        draw(rect, color: color, texture: whiteTexture)
      case .strokeRect(let rect, let width, let color):
        drawStroke(rect, width: width, color: color)
      case .fillRoundedRect(let rect, _, let color):
        // The GLES backend does not yet have a rounded-rectangle shader;
        // preserve the command's bounds and color rather than dropping it.
        draw(rect, color: color, texture: whiteTexture)
      case .strokeRoundedRect(let rect, _, let width, let color):
        drawStroke(rect, width: width, color: color)
      case .text(let position, let text, let color, let scale, let face):
        drawText(text, at: position, color: color, scale: scale, face: face)
      case .pushClip(let rect):
        let clipped = clips.last.flatMap { rect.intersection($0) } ?? (clips.isEmpty ? rect : .zero)
        clips.append(clipped)
        applyClip(clipped, viewport: viewport)
      case .popClip:
        _ = clips.popLast()
        if let clip = clips.last { applyClip(clip, viewport: viewport) } else { glDisable(GLenum(GL_SCISSOR_TEST)) }
      }
    }
  }

  private func draw(
    _ rect: Rect, color: Color, texture: GLuint, uv0: (Float, Float) = (0, 0), uv1: (Float, Float) = (1, 1)
  ) {
    guard rect.size.width > 0, rect.size.height > 0 else { return }
    var quad = GLQuad(
      dst0: (rect.minX, rect.minY), dst1: (rect.maxX, rect.maxY), uv0: uv0, uv1: uv1,
      color: (color.r, color.g, color.b, color.a))
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), instanceVBO)
    withUnsafeBytes(of: &quad) {
      unsafe glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, $0.count, $0.baseAddress)
    }
    glDrawArraysInstanced(GLenum(GL_TRIANGLE_STRIP), 0, 4, 1)
  }

  private func drawStroke(_ rect: Rect, width: Float, color: Color) {
    let border = max(0, width)
    guard border > 0 else { return }
    if rect.size.width <= border * 2 || rect.size.height <= border * 2 {
      draw(rect, color: color, texture: whiteTexture)
      return
    }
    draw(Rect(x: rect.minX, y: rect.minY, width: rect.size.width, height: border), color: color, texture: whiteTexture)
    draw(
      Rect(x: rect.minX, y: rect.maxY - border, width: rect.size.width, height: border), color: color,
      texture: whiteTexture)
    draw(
      Rect(x: rect.minX, y: rect.minY + border, width: border, height: rect.size.height - border * 2), color: color,
      texture: whiteTexture)
    draw(
      Rect(x: rect.maxX - border, y: rect.minY + border, width: border, height: rect.size.height - border * 2),
      color: color, texture: whiteTexture)
  }

  private func drawText(
    _ text: String,
    at position: Point,
    color: Color,
    scale: Float,
    face: FontFace
  ) {
    let metrics = FontMetrics()
    guard let fontAtlas else { return }
    var x = position.x
    for character in text {
      let uv = fontAtlas.glyphUV(character, readable: face == .readable)
      draw(
        Rect(
          x: x,
          y: position.y,
          width: metrics.glyphWidth * scale,
          height: metrics.glyphHeight * scale
        ),
        color: color,
        texture: fontTexture,
        uv0: (uv.0, uv.1),
        uv1: (uv.2, uv.3)
      )
      x += metrics.advance(for: face) * scale
    }
  }

  private func applyClip(_ rect: Rect, viewport: Size) {
    let left = max(0, min(width, Int32(rect.minX.rounded(.down))))
    let right = max(0, min(width, Int32(rect.maxX.rounded(.up))))
    let top = max(0, min(height, Int32(rect.minY.rounded(.down))))
    let bottom = max(0, min(height, Int32(rect.maxY.rounded(.up))))
    let clipWidth = max(0, right - left)
    let clipHeight = max(0, bottom - top)
    glEnable(GLenum(GL_SCISSOR_TEST))
    glScissor(
      left * bufferScale, (height - bottom) * bufferScale,
      clipWidth * bufferScale, clipHeight * bufferScale)
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
    if fontTexture != 0 { unsafe glDeleteTextures(1, &fontTexture) }
    if whiteTexture != 0 { unsafe glDeleteTextures(1, &whiteTexture) }
    if instanceVBO != 0 { unsafe glDeleteBuffers(1, &instanceVBO) }
    if quadVBO != 0 { unsafe glDeleteBuffers(1, &quadVBO) }
    if vao != 0 { unsafe glDeleteVertexArrays(1, &vao) }
    if program != 0 { glDeleteProgram(program) }
    fontTexture = 0
    fontAtlas = nil
    whiteTexture = 0
    instanceVBO = 0
    quadVBO = 0
    vao = 0
    program = 0
    resolutionUniform = -1

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

#endif
