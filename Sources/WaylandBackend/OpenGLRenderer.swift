#if WAYLAND_BACKEND

import CGLES3
import Chroma

/// Owns the OpenGL ES objects used to consume backend-neutral draw commands.
///
/// The caller owns the current EGL context. `setUp()`, `render`, and
/// `cleanup()` must all be called while that context is current.
@MainActor
final class OpenGLRenderer {
  private var program: GLuint = 0
  private var vao: GLuint = 0
  private var quadVBO: GLuint = 0
  private var instanceVBO: GLuint = 0
  private var whiteTexture: GLuint = 0
  private var fontTexture: GLuint = 0
  private var fontAtlas: FontAtlas?
  private var resolutionUniform: GLint = -1

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

  func setUp() throws {
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
    let offsets = [0, 8, 16, 24, 32, 48, 56, 72]
    let sizes: [GLint] = [2, 2, 2, 2, 4, 2, 4, 4]
    for index in offsets.indices {
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

  func render(_ drawList: DrawList, viewport: Size, bufferScale: Int32) {
    let pixelWidth = Int32(viewport.width) * bufferScale
    let pixelHeight = Int32(viewport.height) * bufferScale
    glViewport(0, 0, pixelWidth, pixelHeight)
    glClearColor(0.1, 0.1, 0.2, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glUseProgram(program)
    // Geometry remains in logical coordinates. The scaled viewport renders
    // each logical unit with `bufferScale` pixels.
    glUniform2f(resolutionUniform, viewport.width, viewport.height)
    glBindVertexArray(vao)

    var clips: [Rect] = []
    for command in drawList.commands {
      switch command {
      case .fillRect(let rect, let color):
        draw(rect, color: color, texture: whiteTexture)
      case .strokeRect(let rect, let width, let color):
        drawStroke(rect, width: width, color: color)
      case .fillRoundedRect(let rect, let radii, let color):
        drawShape(rect, radii: radii, color: color)
      case .strokeRoundedRect(let rect, let radii, let width, let color):
        drawShape(rect, radii: radii, borderWidth: width, color: color)
      case .text(let position, let text, let color, let scale, let face):
        drawText(text, at: position, color: color, scale: scale, face: face)
      case .pushClip(let rect):
        let clipped = clips.last.flatMap { rect.intersection($0) } ?? (clips.isEmpty ? rect : .zero)
        clips.append(clipped)
        applyClip(clipped, viewport: viewport, bufferScale: bufferScale)
      case .popClip:
        _ = clips.popLast()
        if let clip = clips.last {
          applyClip(clip, viewport: viewport, bufferScale: bufferScale)
        } else {
          glDisable(GLenum(GL_SCISSOR_TEST))
        }
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

  private func drawShape(
    _ rect: Rect,
    radii requestedRadii: CornerRadii,
    borderWidth: Float = 0,
    color: Color
  ) {
    guard rect.size.width > 0, rect.size.height > 0 else { return }
    let radii = requestedRadii.normalized(for: rect.size)
    // Extend the quad so derivative-based antialiasing is not clipped at the
    // shape's logical bounds.
    let edgePadding: Float = 1
    let padded = Rect(
      x: rect.minX - edgePadding,
      y: rect.minY - edgePadding,
      width: rect.size.width + edgePadding * 2,
      height: rect.size.height + edgePadding * 2)
    var quad = GLQuad(
      dst0: (padded.minX, padded.minY),
      dst1: (padded.maxX, padded.maxY),
      uv0: (0, 0),
      uv1: (1, 1),
      color: (color.r, color.g, color.b, color.a),
      size: (rect.size.width, rect.size.height),
      radii: (radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft),
      shape: (max(0, borderWidth), edgePadding, 1, 0))
    glBindTexture(GLenum(GL_TEXTURE_2D), whiteTexture)
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

  private func applyClip(_ rect: Rect, viewport: Size, bufferScale: Int32) {
    let left = max(0, min(Int32(viewport.width), Int32(rect.minX.rounded(.down))))
    let right = max(0, min(Int32(viewport.width), Int32(rect.maxX.rounded(.up))))
    let top = max(0, min(Int32(viewport.height), Int32(rect.minY.rounded(.down))))
    let bottom = max(0, min(Int32(viewport.height), Int32(rect.maxY.rounded(.up))))
    let clipWidth = max(0, right - left)
    let clipHeight = max(0, bottom - top)
    glEnable(GLenum(GL_SCISSOR_TEST))
    glScissor(
      left * bufferScale, (Int32(viewport.height) - bottom) * bufferScale,
      clipWidth * bufferScale, clipHeight * bufferScale)
  }

  func cleanup() {
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
  }
}

#endif
