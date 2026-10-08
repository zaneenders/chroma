import CEGL
import CGLES3
import Chroma
import Foundation
import Testing

@testable import WaylandBackend

@Suite(.serialized) @MainActor
struct OpenGLRenderingTests {
  @Test func adjacentGlyphsUseOneUploadAndDraw() throws {
    let target = try EGLTestTarget()
    let text = "Batch"
    var list = DrawList()
    list.text(text, at: Point(x: 4, y: 4), color: .white, scale: 0.75)
    try target.render(list)
    #expect(target.renderer.lastInstanceCount == text.count)
    #expect(target.renderer.lastDrawCallCount == 1)
    #expect(target.renderer.lastUploadCallCount == 1)
    #expect(target.renderer.lastUploadByteCount == text.count * MemoryLayout<GLQuad>.stride)
    let pixels = try target.pixels()
    #expect(stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 220 })
  }

  @Test func equivalentEffectiveClipsDoNotSplitABatch() throws {
    let target = try EGLTestTarget()
    var list = DrawList()
    list.fillRect(Rect(x: 0, y: 0, width: 8, height: 8), color: .white)
    list.pushClip(Rect(origin: .zero, size: target.viewport))
    list.fillRect(Rect(x: 8, y: 0, width: 8, height: 8), color: .white)
    list.pushClip(Rect(x: -10, y: -10, width: 100, height: 100))
    list.fillRect(Rect(x: 16, y: 0, width: 8, height: 8), color: .white)
    list.popClip()
    list.popClip()
    list.fillRect(Rect(x: 24, y: 0, width: 8, height: 8), color: .white)
    try target.render(list)
    #expect(target.renderer.lastInstanceCount == 4)
    #expect(target.renderer.lastDrawCallCount == 1)
  }

  @Test func nestedClipsRestoreAtBufferScaleTwo() throws {
    let target = try EGLTestTarget(bufferScale: 2)
    var list = DrawList()
    list.fillRect(Rect(origin: .zero, size: target.viewport), color: Color(r: 1, g: 0, b: 0, a: 1))
    list.pushClip(Rect(x: 8, y: 8, width: 16, height: 16))
    list.fillRect(Rect(origin: .zero, size: target.viewport), color: Color(r: 0, g: 1, b: 0, a: 1))
    list.pushClip(Rect(x: 12, y: 12, width: 20, height: 20))
    list.fillRect(Rect(origin: .zero, size: target.viewport), color: Color(r: 0, g: 0, b: 1, a: 1))
    list.popClip()
    list.fillRect(Rect(x: 8, y: 8, width: 4, height: 4), color: .white)
    list.popClip()
    list.fillRect(Rect(x: 0, y: 0, width: 4, height: 4), color: .white)
    try target.render(list)
    #expect(target.renderer.lastDrawCallCount == 5)
    let pixels = try target.pixels()
    #expect(target.rgb(pixels, x: 12, y: 12) == [255, 0, 0])
    #expect(target.rgb(pixels, x: 20, y: 28) == [0, 255, 0])
    #expect(target.rgb(pixels, x: 28, y: 28) == [0, 0, 255])
    #expect(target.rgb(pixels, x: 20, y: 20) == [255, 255, 255])
    #expect(target.rgb(pixels, x: 52, y: 52) == [255, 0, 0])
    #expect(target.rgb(pixels, x: 3, y: 3) == [255, 255, 255])
  }

  @Test func imageGenerationsAndDimensionsFlushBeforeTextureReplacement() throws {
    let target = try EGLTestTarget()
    let red = try ImageResource(id: ImageID("changing"), width: 1, height: 1, rgba8: Data([255, 0, 0, 255]))
    let blue = try red.replacingPixels(width: 1, height: 1, rgba8: Data([0, 0, 255, 255]))
    let green = try ImageResource(
      id: red.id, generation: blue.generation, width: 2, height: 1,
      rgba8: Data([0, 255, 0, 255, 0, 255, 0, 255]))
    var list = DrawList()
    for (index, image) in [red, red, blue, green, red].enumerated() {
      list.append(DrawQuad(rect: Rect(x: Float(index * 12), y: 4, width: 10, height: 10), texture: .image(image)))
    }
    try target.render(list)
    #expect(target.renderer.lastInstanceCount == 5)
    #expect(target.renderer.lastDrawCallCount == 4)
    let pixels = try target.pixels()
    for (index, color) in [[255, 0, 0], [255, 0, 0], [0, 0, 255], [0, 255, 0], [255, 0, 0]].enumerated() {
      #expect(target.rgb(pixels, x: index * 12 + 4, y: 8) == color.map { UInt8($0) })
    }
  }

  @Test func batchingMatchesIndividualDrawsForShapesTexturesAndTransparency() throws {
    let target = try EGLTestTarget()
    let image = try ImageResource(
      id: ImageID("translucent"), width: 1, height: 1, rgba8: Data([255, 80, 0, 160]))
    var list = DrawList()
    list.fillRect(Rect(x: 4, y: 4, width: 48, height: 48), color: Color(r: 0, g: 0, b: 1, a: 0.5))
    list.append(
      DrawQuad(
        rect: Rect(x: 8, y: 8, width: 40, height: 40),
        colors: CornerColors(
          topLeft: Color(r: 1, g: 0, b: 0, a: 0.7), topRight: Color(r: 0, g: 1, b: 0, a: 0.5),
          bottomRight: Color(r: 0, g: 0, b: 1, a: 1), bottomLeft: .white),
        radii: CornerRadii(6), borderThickness: 3, edgeSoftness: 0.5))
    list.pushClip(Rect(x: 10, y: 10, width: 32, height: 32))
    list.fillRoundedRect(Rect(x: 4, y: 4, width: 48, height: 48), radius: 8, color: Color(r: 0, g: 1, b: 0, a: 0.4))
    list.append(DrawQuad(rect: Rect(x: 18, y: 18, width: 20, height: 20), texture: .image(image)))
    list.text("AB", at: Point(x: 14, y: 20), color: .white, scale: 0.5)
    list.fillRect(Rect(x: 20, y: 20, width: 12, height: 12), color: Color(r: 1, g: 0, b: 0, a: 0.5))
    list.popClip()
    try target.render(list)
    #expect(target.renderer.lastInstanceCount == 7)
    #expect(target.renderer.lastDrawCallCount == 5)
    let batched = try target.pixels()
    target.beginFrame()
    var clips: [Rect] = []
    let root = Rect(origin: .zero, size: target.viewport)
    for entry in list.commands {
      switch entry {
      case .pushClip(let rect): clips.append((clips.last ?? root).intersection(rect) ?? .zero)
      case .popClip: _ = clips.popLast()
      case .quad(let quad):
        target.renderer.render(
          DrawList(commands: [.pushClip(clips.last ?? root), .quad(quad), .popClip]),
          viewport: target.viewport, bufferScale: target.bufferScale)
      }
    }
    #expect(try target.pixels() == batched)
  }

  @Test func largeRunsUseBoundedStorageAndPreserveEarlierUploads() throws {
    let target = try EGLTestTarget()
    var list = DrawList()
    for (index, color) in [Color(r: 1, g: 0, b: 0, a: 1), Color(r: 0, g: 1, b: 0, a: 1), Color(r: 0, g: 0, b: 1, a: 1)]
      .enumerated()
    {
      let count = index == 2 ? 5 : OpenGLRenderer.maximumBatchInstanceCount
      for _ in 0..<count {
        list.fillRect(Rect(x: Float(index * 16), y: 4, width: 12, height: 12), color: color)
      }
    }
    for _ in 0..<2 {
      try target.render(list)
      #expect(target.renderer.lastInstanceCount == 2 * OpenGLRenderer.maximumBatchInstanceCount + 5)
      #expect(target.renderer.lastDrawCallCount == 3)
      #expect(target.renderer.lastUploadCallCount == 3)
      #expect(target.renderer.lastUploadByteCount == target.renderer.lastInstanceCount * MemoryLayout<GLQuad>.stride)
      var size: GLint = 0
      unsafe glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
      #expect(Int(size) == 5 * MemoryLayout<GLQuad>.stride)
      let pixels = try target.pixels()
      #expect(target.rgb(pixels, x: 4, y: 8) == [255, 0, 0])
      #expect(target.rgb(pixels, x: 20, y: 8) == [0, 255, 0])
      #expect(target.rgb(pixels, x: 36, y: 8) == [0, 0, 255])
    }
  }

  @Test func culledEmptyAndFollowingFramesResetWorkAndScissor() throws {
    let target = try EGLTestTarget()
    var list = DrawList()
    list.pushClip(Rect(x: 8, y: 8, width: 12, height: 12))
    list.fillRect(Rect(origin: .zero, size: target.viewport), color: .white)
    // Deliberately leave a clip open; it must not restrict the next frame's clear.
    try target.render(list)
    #expect(target.renderer.lastDrawCallCount == 1)
    list = DrawList()
    list.fillRect(Rect(x: 100, y: 100, width: 4, height: 4), color: .white)
    list.fillRect(Rect(x: 1, y: 1, width: 0, height: 4), color: .white)
    list.pushClip(Rect.zero)
    list.fillRect(Rect(origin: .zero, size: target.viewport), color: .white)
    list.popClip()
    try target.render(list)
    #expect(target.renderer.lastInstanceCount == 0)
    #expect(target.renderer.lastDrawCallCount == 0)
    #expect(target.renderer.lastUploadCallCount == 0)
    #expect(target.renderer.lastUploadByteCount == 0)
    let pixels = try target.pixels()
    #expect(target.rgb(pixels, x: 0, y: 0) == target.rgb(pixels, x: 10, y: 10))
    #expect(target.rgb(pixels, x: 10, y: 10).allSatisfy { $0 < 100 })
  }

  @Test func instanceLayoutMatchesTheShaderAttributes() {
    #expect(MemoryLayout<GLQuad>.stride == 136)
    #expect(MemoryLayout<GLQuad>.offset(of: \.color) == 32)
    #expect(MemoryLayout<GLQuad>.offset(of: \.shape) == 72)
    #expect(MemoryLayout<GLQuad>.offset(of: \.bottomLeft) == 120)
  }
}

// Owns all EGL handles and scopes pixel-buffer access to synchronous C calls.
@safe @MainActor
private final class EGLTestTarget {
  let viewport = Size(width: 64, height: 64)
  let bufferScale: Int32
  let renderer = OpenGLRenderer()
  private var display: EGLDisplay?
  private var context: EGLContext?
  private var surface: EGLSurface?

  init(bufferScale: Int32 = 1) throws {
    self.bufferScale = bufferScale
    do {
      unsafe display = eglGetPlatformDisplay(EGLenum(EGL_PLATFORM_SURFACELESS_MESA), nil, nil)
      let initialized = unsafe display != nil && eglInitialize(display, nil, nil) == EGL_TRUE
      try #require(initialized)
      try #require(eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) == EGL_TRUE)
      let attributes: [EGLint] = [
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE,
      ]
      var config: EGLConfig?
      var count: EGLint = 0
      attributes.withUnsafeBufferPointer {
        _ = unsafe eglChooseConfig(display, $0.baseAddress, &config, 1, &count)
      }
      let configured = unsafe config != nil && count > 0
      try #require(configured)
      let contextAttributes: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE]
      unsafe context = contextAttributes.withUnsafeBufferPointer {
        unsafe eglCreateContext(display, config, nil, $0.baseAddress)
      }
      let surfaceAttributes: [EGLint] = [EGL_WIDTH, 64 * bufferScale, EGL_HEIGHT, 64 * bufferScale, EGL_NONE]
      unsafe surface = surfaceAttributes.withUnsafeBufferPointer {
        unsafe eglCreatePbufferSurface(display, config, $0.baseAddress)
      }
      let created = unsafe context != nil && surface != nil
      try #require(created)
      try #require(unsafe eglMakeCurrent(display, surface, surface, context) == EGL_TRUE)
      try renderer.setUp()
    } catch {
      cleanup()
      throw error
    }
  }

  isolated deinit { cleanup() }

  private func cleanup() {
    if unsafe context != nil { renderer.cleanup() }
    if let display = unsafe display {
      _ = unsafe eglMakeCurrent(display, nil, nil, nil)
      if let surface = unsafe surface { _ = unsafe eglDestroySurface(display, surface) }
      if let context = unsafe context { _ = unsafe eglDestroyContext(display, context) }
      _ = unsafe eglTerminate(display)
    }
    unsafe surface = nil
    unsafe context = nil
    unsafe display = nil
  }

  func beginFrame() {
    renderer.beginFrame(width: 64, height: 64, bufferScale: bufferScale)
  }

  func render(_ list: DrawList) throws {
    beginFrame()
    renderer.render(list, viewport: viewport, bufferScale: bufferScale)
    try #require(glGetError() == GLenum(GL_NO_ERROR))
  }

  func pixels() throws -> [UInt8] {
    let side = Int(64 * bufferScale)
    var result = [UInt8](repeating: 0, count: side * side * 4)
    result.withUnsafeMutableBytes {
      unsafe glReadPixels(0, 0, GLsizei(side), GLsizei(side), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
    }
    try #require(glGetError() == GLenum(GL_NO_ERROR))
    return result
  }

  func rgb(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
    let side = Int(64 * bufferScale)
    let offset = ((side - 1 - y) * side + x) * 4
    return Array(pixels[offset..<(offset + 3)])
  }
}
