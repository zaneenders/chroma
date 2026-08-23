#if WAYLAND_BACKEND

import CEGL
import CGLES3
import Chroma
import CWaylandClient
import CWaylandEGL
import CWaylandProtocols
import Foundation

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

  private var width: Int32
  private var height: Int32
  private var running = true
  private var configured = false

  private var display: OpaquePointer?
  private var registry: OpaquePointer?
  private var compositor: OpaquePointer?
  private var wmBase: OpaquePointer?
  private var shm: OpaquePointer?
  private var seat: OpaquePointer?
  private var pointer: OpaquePointer?
  private var surface: OpaquePointer?
  private var xdgSurface: OpaquePointer?
  private var toplevel: OpaquePointer?

  private let input = InputAccumulator()
  private let cursor = WaylandCursor()
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
  private var resolutionUniform: GLint = -1

  private static var compositorInterface: wl_interface = unsafe wl_compositor_interface
  private static var wmBaseInterface: wl_interface = unsafe xdg_wm_base_interface
  private static var seatInterface: wl_interface = unsafe wl_seat_interface
  private static var shmInterface: wl_interface = unsafe wl_shm_interface

  public init(size: Size = Size(width: 800, height: 600)) {
    width = max(1, Int32(size.width))
    height = max(1, Int32(size.height))
  }


  public func run(title: String = "Hello Triangle") throws {
    do {
      try setUpWayland(title: title)
      try setUpEGL()
      setUpGL()
      drawFrame()

      while running, let display, unsafe wl_display_dispatch(display) != -1 {
        // The current Block API is static, but redraw after every event so
        // configure/expose events and future interaction state are reflected.
        drawFrame()
      }
    } catch {
      cleanup()
      throw error
    }
    cleanup()
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
          wl_registry_bind(registry, name, &compositorInterface, min(version, 4)))
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
      if hasPointer {
        guard renderer.pointer == nil, let seat else { return }
        renderer.pointer = unsafe wl_seat_get_pointer(seat)
        if let pointer = renderer.pointer {
          unsafe wl_pointer_add_listener(
            pointer, &pointerListener, Unmanaged.passUnretained(renderer).toOpaque())
        }
      } else if let pointer = renderer.pointer {
        unsafe wl_pointer_destroy(pointer)
        renderer.pointer = nil
      }
    },
    name: { _, _, _ in }
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
      let delta = fixedToFloat(value)
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
      if let eglWindow = renderer.eglWindow {
        unsafe wl_egl_window_resize(eglWindow, width, height, 0, 0)
      }
    }

  private static var toplevelListener = unsafe xdg_toplevel_listener(
    configure: configureCallback,
    close: { data, _ in
      guard let data else { return }
      unsafe Unmanaged<WaylandRenderer>.fromOpaque(data).takeUnretainedValue().running = false
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

    eglWindow = unsafe wl_egl_window_create(surface, width, height)
    guard let eglWindow else { throw WaylandError("wl_egl_window_create failed") }
    eglSurface = unsafe eglCreateWindowSurface(
      eglDisplay, config, EGLNativeWindowType(bitPattern: eglWindow), nil)
    guard eglSurface != nil else { throw WaylandError("eglCreateWindowSurface failed") }
    guard unsafe eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext) == EGL_TRUE else {
      throw WaylandError("eglMakeCurrent failed")
    }
    _ = unsafe eglSwapInterval(eglDisplay, 1)
  }

  private func compileShader(_ type: GLenum, source: String) -> GLuint {
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
      fatalError("GLES shader compilation failed: \(message)")
    }
    return shader
  }

  private func setUpGL() {
    let vertex = compileShader(GLenum(GL_VERTEX_SHADER), source: vertexShader)
    let fragment = compileShader(GLenum(GL_FRAGMENT_SHADER), source: fragmentShader)
    program = glCreateProgram()
    glAttachShader(program, vertex)
    glAttachShader(program, fragment)
    glLinkProgram(program)
    glDeleteShader(vertex)
    glDeleteShader(fragment)

    var linked: GLint = 0
    unsafe glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linked)
    guard linked != 0 else { fatalError("GLES shader program failed to link") }

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

  private func makeTexture(width: Int, height: Int, pixels: [UInt8]) -> GLuint {
    var texture: GLuint = 0
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    pixels.withUnsafeBytes {
      unsafe glTexImage2D(
        GLenum(GL_TEXTURE_2D), 0, GLint(GL_RGBA), GLsizei(width), GLsizei(height), 0,
        GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
    }
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    return texture
  }

  private func makeFontTexture() {
    let metrics = FontMetrics()
    let first = 32
    let last = 126
    let atlasWidth = (last - first + 1) * Int(metrics.cellAdvance)
    let atlasHeight = Int(metrics.glyphHeight)
    let glyphs = FontAtlas.buildFont()
    var pixels = [UInt8](repeating: 0, count: atlasWidth * atlasHeight * 4)
    for character in first...last {
      let xOffset = (character - first) * Int(metrics.cellAdvance)
      for y in 0..<Int(metrics.glyphHeight) {
        let row = Array(glyphs[character].rows[y])
        for x in 0..<Int(metrics.glyphWidth) where row[x] == "1" {
          let offset = (y * atlasWidth + xOffset + x) * 4
          pixels[offset] = 255; pixels[offset + 1] = 255
          pixels[offset + 2] = 255; pixels[offset + 3] = 255
        }
      }
    }
    fontTexture = makeTexture(width: atlasWidth, height: atlasHeight, pixels: pixels)
  }

  // MARK: DrawList consumption

  private func drawFrame() {
    guard eglDisplay != nil, eglSurface != nil else { return }
    glViewport(0, 0, width, height)
    glClearColor(0.1, 0.1, 0.2, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glUseProgram(program)
    glUniform2f(resolutionUniform, Float(width), Float(height))
    glBindVertexArray(vao)

    // Pointer input is accumulated from the wl_pointer listener and drained
    // once per frame, matching the Metal backend's event coalescing.
    updateFrameRate()
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
      case .text(let position, let text, let color, let scale, _):
        drawText(text, at: position, color: color, scale: scale)
      case .pushClip(let rect):
        let clipped = clips.last.flatMap { rect.intersection($0) } ?? (clips.isEmpty ? rect : .zero)
        clips.append(clipped)
        applyClip(clipped, viewport: viewport)
      case .popClip:
        _ = clips.popLast()
        if let clip = clips.last { applyClip(clip, viewport: viewport) }
        else { glDisable(GLenum(GL_SCISSOR_TEST)) }
      }
    }
  }

  private func draw(_ rect: Rect, color: Color, texture: GLuint, uv0: (Float, Float) = (0, 0), uv1: (Float, Float) = (1, 1)) {
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
      draw(rect, color: color, texture: whiteTexture); return
    }
    draw(Rect(x: rect.minX, y: rect.minY, width: rect.size.width, height: border), color: color, texture: whiteTexture)
    draw(Rect(x: rect.minX, y: rect.maxY - border, width: rect.size.width, height: border), color: color, texture: whiteTexture)
    draw(Rect(x: rect.minX, y: rect.minY + border, width: border, height: rect.size.height - border * 2), color: color, texture: whiteTexture)
    draw(Rect(x: rect.maxX - border, y: rect.minY + border, width: border, height: rect.size.height - border * 2), color: color, texture: whiteTexture)
  }

  private func drawText(_ text: String, at position: Point, color: Color, scale: Float) {
    let metrics = FontMetrics()
    let atlasWidth = 95 * metrics.cellAdvance
    var x = position.x
    for byte in text.utf8 {
      let character = min(126, max(32, Int(byte)))
      let offset = Float(character - 32) * metrics.cellAdvance
      draw(
        Rect(x: x, y: position.y, width: metrics.glyphWidth * scale, height: metrics.glyphHeight * scale),
        color: color, texture: fontTexture,
        uv0: (offset / atlasWidth, 0), uv1: ((offset + metrics.glyphWidth) / atlasWidth, 1))
      x += metrics.cellAdvance * scale
    }
  }

  private func applyClip(_ rect: Rect, viewport: Size) {
    let x = max(0, Int32(rect.minX.rounded(.down)))
    let top = max(0, Int32(rect.minY.rounded(.down)))
    let clipWidth = max(0, min(width - x, Int32(rect.size.width.rounded(.up))))
    let clipHeight = max(0, min(height - top, Int32(rect.size.height.rounded(.up))))
    glEnable(GLenum(GL_SCISSOR_TEST))
    glScissor(x, max(0, height - top - clipHeight), clipWidth, clipHeight)
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
    if program != 0 { glDeleteProgram(program) }
    if let eglDisplay {
      _ = unsafe eglMakeCurrent(eglDisplay, nil, nil, nil)
      if let eglSurface { _ = unsafe eglDestroySurface(eglDisplay, eglSurface) }
      if let eglContext { _ = unsafe eglDestroyContext(eglDisplay, eglContext) }
      _ = unsafe eglTerminate(eglDisplay)
    }
    if let eglWindow { unsafe wl_egl_window_destroy(eglWindow) }
    cursor.cleanup()
    if let pointer { unsafe wl_pointer_destroy(pointer) }
    if let seat { unsafe wl_seat_destroy(seat) }
    if let shm { unsafe wl_shm_destroy(shm) }
    if let toplevel { unsafe xdg_toplevel_destroy(toplevel) }
    if let xdgSurface { unsafe xdg_surface_destroy(xdgSurface) }
    if let surface { unsafe wl_surface_destroy(surface) }
    if let wmBase { unsafe xdg_wm_base_destroy(wmBase) }
    if let compositor { unsafe wl_compositor_destroy(compositor) }
    if let registry { unsafe wl_registry_destroy(registry) }
    if let display { unsafe wl_display_disconnect(display) }

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
