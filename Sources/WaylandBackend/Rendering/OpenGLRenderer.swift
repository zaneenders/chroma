import CGLES3
import Chroma

@diagnose(
  StrictMemorySafety, as: ignored,
  reason:
    "OpenGL copies scoped upload buffers synchronously; buffer sizes and vertex offsets are checked before C calls.")
/// Draw-list encoder for a current OpenGL ES 3 context.
/// Call setup, frame encoding, and cleanup on the context's owning thread.
@MainActor
public final class OpenGLRenderer {
  public init() {}

  public private(set) var lastInstanceCount = 0
  public private(set) var lastDrawCallCount = 0
  /// Instance-buffer payload uploads, excluding texture uploads and buffer orphaning.
  public private(set) var lastUploadCallCount = 0
  public private(set) var lastUploadByteCount = 0
  private var program: GLuint = 0
  private var vao: GLuint = 0
  private var quadVBO: GLuint = 0
  private var instanceVBO: GLuint = 0
  private var whiteTexture: GLuint = 0
  private var fontTexture: GLuint = 0
  private var fontAtlas: FontAtlas?
  private var resolutionUniform: GLint = -1

  // Bound staging and each GPU backing store to about 544 KiB, even for huge draw lists.
  static let maximumBatchInstanceCount = 4096
  private var instances: [GLQuad] = []
  private var batchKey: GLTextureKey?
  private var batchTexture: GLuint = 0
  private var batchClip = Rect.zero

  private struct CachedImageTexture {
    var generation: UInt64
    var width: Int
    var height: Int
    var texture: GLuint
    var byteCount: Int
    var lastUsedFrame: UInt64
  }
  private var imageTextures: [ImageID: CachedImageTexture] = [:]
  private var imageTextureBytes = 0
  private var imageFrame: UInt64 = 0
  private let maximumImageTextureCount = 128
  private let maximumImageTextureBytes = 256 * 1024 * 1024

  private func compileShader(_ type: GLenum, source: String, stage: String) throws -> GLuint {
    let shader = glCreateShader(type)
    source.withCString { sourcePointer in
      var pointer: UnsafePointer<GLchar>? = sourcePointer
      let length = GLint(exactly: source.utf8.count)
      precondition(length != nil)
      var byteCount = length!
      unsafe glShaderSource(shader, 1, &pointer, &byteCount)
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

  public func setUp() throws {
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
    corners.span.bytes.withUnsafeBytes {
      unsafe glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count, $0.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 8, nil)

    unsafe glGenBuffers(1, &instanceVBO)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), instanceVBO)
    instances.reserveCapacity(Self.maximumBatchInstanceCount)
    let stride = GLsizei(MemoryLayout<GLQuad>.stride)
    let offsets = [
      MemoryLayout<GLQuad>.offset(of: \.dst0)!, MemoryLayout<GLQuad>.offset(of: \.dst1)!,
      MemoryLayout<GLQuad>.offset(of: \.uv0)!, MemoryLayout<GLQuad>.offset(of: \.uv1)!,
      MemoryLayout<GLQuad>.offset(of: \.color)!, MemoryLayout<GLQuad>.offset(of: \.size)!,
      MemoryLayout<GLQuad>.offset(of: \.radii)!, MemoryLayout<GLQuad>.offset(of: \.shape)!,
      MemoryLayout<GLQuad>.offset(of: \.topRight)!,
      MemoryLayout<GLQuad>.offset(of: \.bottomRight)!,
      MemoryLayout<GLQuad>.offset(of: \.bottomLeft)!,
    ]
    let sizes: [GLint] = [2, 2, 2, 2, 4, 2, 4, 4, 4, 4, 4]
    for index in offsets.indices {
      let attribute = GLuint(index + 1)
      glEnableVertexAttribArray(attribute)
      precondition(offsets[index] + Int(sizes[index]) * MemoryLayout<Float>.size <= Int(stride))
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

  private func uploadTexture(
    _ bytes: RawSpan, width: Int, height: Int, format: GLenum, level: GLint
  ) {
    precondition(format == GLenum(GL_RED) || format == GLenum(GL_RGBA))
    precondition(width > 0 && height > 0 && level >= 0)
    guard let glWidth = GLsizei(exactly: width), let glHeight = GLsizei(exactly: height) else {
      preconditionFailure("Texture dimensions exceed GLsizei")
    }
    let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: format == GLenum(GL_RED) ? 1 : 4)
    let (byteCount, sizeOverflow) = rowBytes.multipliedReportingOverflow(by: height)
    precondition(!rowOverflow && !sizeOverflow && byteCount == bytes.byteCount)
    var alignment: GLint = 0
    var rowLength: GLint = 0
    var skipRows: GLint = 0
    var skipPixels: GLint = 0
    var pixelBuffer: GLint = 0
    unsafe glGetIntegerv(GLenum(GL_UNPACK_ALIGNMENT), &alignment)
    unsafe glGetIntegerv(GLenum(GL_UNPACK_ROW_LENGTH), &rowLength)
    unsafe glGetIntegerv(GLenum(GL_UNPACK_SKIP_ROWS), &skipRows)
    unsafe glGetIntegerv(GLenum(GL_UNPACK_SKIP_PIXELS), &skipPixels)
    unsafe glGetIntegerv(GLenum(GL_PIXEL_UNPACK_BUFFER_BINDING), &pixelBuffer)
    glBindBuffer(GLenum(GL_PIXEL_UNPACK_BUFFER), 0)
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
    glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), 0)
    glPixelStorei(GLenum(GL_UNPACK_SKIP_ROWS), 0)
    glPixelStorei(GLenum(GL_UNPACK_SKIP_PIXELS), 0)
    defer {
      glBindBuffer(GLenum(GL_PIXEL_UNPACK_BUFFER), GLuint(bitPattern: pixelBuffer))
      glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), alignment)
      glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), rowLength)
      glPixelStorei(GLenum(GL_UNPACK_SKIP_ROWS), skipRows)
      glPixelStorei(GLenum(GL_UNPACK_SKIP_PIXELS), skipPixels)
    }
    bytes.withUnsafeBytes { buffer in
      unsafe glTexImage2D(
        GLenum(GL_TEXTURE_2D), level, GLint(format), glWidth, glHeight, 0,
        format, GLenum(GL_UNSIGNED_BYTE), buffer.baseAddress)
    }
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
    uploadTexture(pixels.span.bytes, width: width, height: height, format: GLenum(GL_RGBA), level: 0)
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
    var unpackAlignment: GLint = 0
    unsafe glGetIntegerv(GLenum(GL_UNPACK_ALIGNMENT), &unpackAlignment)
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
    defer { glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), unpackAlignment) }

    for (level, mip) in atlas.mipLevels.enumerated() {
      uploadTexture(
        mip.pixels.span.bytes, width: mip.width, height: mip.height,
        format: GLenum(GL_RED), level: GLint(level))
    }
    glTexParameteri(
      GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    fontTexture = texture
  }

  public func beginFrame(width: Int32, height: Int32, bufferScale: Int32) {
    glViewport(0, 0, width * bufferScale, height * bufferScale)
    glDisable(GLenum(GL_SCISSOR_TEST))
    glClearColor(0.1, 0.1, 0.2, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glUseProgram(program)
    glUniform2f(resolutionUniform, Float(width), Float(height))
    glBindVertexArray(vao)
  }

  public func render(_ drawList: DrawList, viewport: Size, bufferScale: Int32) {
    lastInstanceCount = 0
    lastDrawCallCount = 0
    lastUploadCallCount = 0
    lastUploadByteCount = 0
    imageFrame &+= 1
    let root = Rect(origin: .zero, size: viewport)
    var clips: [Rect] = []
    for entry in drawList.culled(to: viewport).commands {
      switch entry {
      case .quad(let quad):
        guard quad.rect.size.width > 0, quad.rect.size.height > 0 else { continue }
        let key = GLTextureKey(quad.texture)
        let clip = clips.last ?? root
        if key != batchKey || clip != batchClip || instances.count == Self.maximumBatchInstanceCount {
          flushBatch(viewport: viewport, bufferScale: bufferScale)
        }
        if instances.isEmpty {
          // Flush before resolving a new image generation: resolution can delete its old texture.
          switch quad.texture {
          case .white: batchTexture = whiteTexture
          case .fontAtlas: batchTexture = fontTexture
          case .image(let image):
            guard let texture = imageTexture(for: image) else { continue }
            batchTexture = texture
          }
          batchKey = key
          batchClip = clip
        }
        instances.append(GLQuad(quad))
      case .pushClip(let rect): clips.append((clips.last ?? root).intersection(rect) ?? .zero)
      case .popClip: _ = clips.popLast()
      }
    }
    flushBatch(viewport: viewport, bufferScale: bufferScale)
    glDisable(GLenum(GL_SCISSOR_TEST))
    evictImageTexturesIfNeeded()
  }

  private func flushBatch(viewport: Size, bufferScale: Int32) {
    guard !instances.isEmpty else { return }
    precondition(instances.count <= Self.maximumBatchInstanceCount)
    let byteCount = instances.count * MemoryLayout<GLQuad>.stride
    glBindTexture(GLenum(GL_TEXTURE_2D), batchTexture)
    applyClip(batchClip, viewport: viewport, bufferScale: bufferScale)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), instanceVBO)
    // Orphan before each upload. GLES keeps prior draws' storage alive; no unsynchronized overwrite
    // or fences are needed. Allocate only this payload, always below the staging limit.
    glBufferData(GLenum(GL_ARRAY_BUFFER), byteCount, nil, GLenum(GL_STREAM_DRAW))
    instances.span.bytes.withUnsafeBytes { bytes in
      precondition(bytes.count == byteCount)
      unsafe glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, bytes.count, bytes.baseAddress)
    }
    glDrawArraysInstanced(GLenum(GL_TRIANGLE_STRIP), 0, 4, GLsizei(instances.count))
    lastInstanceCount += instances.count
    lastDrawCallCount += 1
    lastUploadCallCount += 1
    lastUploadByteCount += byteCount
    instances.removeAll(keepingCapacity: true)
    batchKey = nil
  }

  private func imageTexture(for image: ImageResource) -> GLuint? {
    if var cached = imageTextures[image.id],
      cached.generation == image.generation,
      cached.width == image.width,
      cached.height == image.height
    {
      cached.lastUsedFrame = imageFrame
      imageTextures[image.id] = cached
      return cached.texture
    }
    if let stale = imageTextures.removeValue(forKey: image.id) {
      var texture = stale.texture
      unsafe glDeleteTextures(1, &texture)
      imageTextureBytes -= stale.byteCount
    }
    var texture: GLuint = 0
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    uploadTexture(
      image.rgba8.bytes, width: image.width, height: image.height,
      format: GLenum(GL_RGBA), level: 0)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    let byteCount = image.width * image.height * 4
    imageTextures[image.id] = CachedImageTexture(
      generation: image.generation, width: image.width, height: image.height,
      texture: texture, byteCount: byteCount, lastUsedFrame: imageFrame)
    imageTextureBytes += byteCount
    return texture
  }

  private func evictImageTexturesIfNeeded() {
    while imageTextures.count > maximumImageTextureCount
      || imageTextureBytes > maximumImageTextureBytes
    {
      guard let oldest = imageTextures.min(by: { $0.value.lastUsedFrame < $1.value.lastUsedFrame }) else {
        break
      }
      var texture = oldest.value.texture
      unsafe glDeleteTextures(1, &texture)
      imageTextureBytes -= oldest.value.byteCount
      imageTextures.removeValue(forKey: oldest.key)
    }
  }

  private func applyClip(_ rect: Rect, viewport: Size, bufferScale: Int32) {
    let width = Int32(viewport.width)
    let height = Int32(viewport.height)
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

  public func cleanup() {
    for cached in imageTextures.values {
      var texture = cached.texture
      unsafe glDeleteTextures(1, &texture)
    }
    imageTextures.removeAll()
    imageTextureBytes = 0
    instances.removeAll()
    batchKey = nil
    batchTexture = 0
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
