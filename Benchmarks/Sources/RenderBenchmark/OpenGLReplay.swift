#if os(Linux)
import CEGL
import CGLES3
import Chroma
import WaylandBackend

/// Offscreen driver replay, not Wayland dispatch/presentation or a GPU timer query.
@MainActor
final class OpenGLReplay {
  private var display: EGLDisplay?
  private var surface: EGLSurface?
  private var context: EGLContext?
  private let renderer = OpenGLRenderer()
  private(set) var info: [String: String] = [:]
  var work: [String: Int] {
    [
      "instances": renderer.lastInstanceCount,
      "drawCalls": renderer.lastDrawCallCount,
      "uploadCalls": renderer.lastUploadCallCount,
      "uploadBytes": renderer.lastUploadByteCount,
    ]
  }

  init(viewport: Size) throws {
    guard viewport.width.isFinite, viewport.height.isFinite,
      viewport.width >= 1, viewport.height >= 1, viewport.width <= 8192, viewport.height <= 8192
    else { throw BenchmarkError.failed("Unsupported OpenGL raster dimensions (maximum 8192 per axis)") }
    do {
      display = unsafe eglGetPlatformDisplay(EGLenum(EGL_PLATFORM_SURFACELESS_MESA), nil, nil)
      guard display != nil, unsafe eglInitialize(display, nil, nil) == EGL_TRUE,
        eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) == EGL_TRUE
      else { throw BenchmarkError.failed("Surfaceless EGL / OpenGL ES unavailable") }
      let attributes: [EGLint] = [
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR, EGL_NONE,
      ]
      var config: EGLConfig?
      var count: EGLint = 0
      attributes.withUnsafeBufferPointer {
        _ = unsafe eglChooseConfig(display, $0.baseAddress, &config, 1, &count)
      }
      guard count > 0, config != nil else { throw BenchmarkError.failed("No EGL ES3 pbuffer config") }
      let contextAttributes: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE]
      context = contextAttributes.withUnsafeBufferPointer {
        unsafe eglCreateContext(display, config, nil, $0.baseAddress)
      }
      let surfaceAttributes: [EGLint] = [
        EGL_WIDTH, EGLint(viewport.width.rounded(.up)),
        EGL_HEIGHT, EGLint(viewport.height.rounded(.up)), EGL_NONE,
      ]
      surface = surfaceAttributes.withUnsafeBufferPointer {
        unsafe eglCreatePbufferSurface(display, config, $0.baseAddress)
      }
      guard context != nil, surface != nil,
        unsafe eglMakeCurrent(display, surface, surface, context) == EGL_TRUE
      else { throw BenchmarkError.failed("Could not make EGL ES3 context current") }
      try renderer.setUp()
      for (name, key) in [("vendor", GL_VENDOR), ("renderer", GL_RENDERER), ("version", GL_VERSION)] {
        if let value = glGetString(GLenum(key)) { info[name] = unsafe String(cString: value) }
      }
    } catch {
      cleanup()
      throw error
    }
  }

  isolated deinit { cleanup() }

  private func cleanup() {
    if context != nil { renderer.cleanup() }
    if let display {
      _ = unsafe eglMakeCurrent(display, nil, nil, nil)
      if let surface { _ = unsafe eglDestroySurface(display, surface) }
      if let context { _ = unsafe eglDestroyContext(display, context) }
      _ = unsafe eglTerminate(display)
    }
    surface = nil
    context = nil
    display = nil
  }

  func render(_ list: DrawList, viewport: Size) throws -> (cpu: Double, completion: Double) {
    guard unsafe eglGetCurrentContext() == context else {
      throw BenchmarkError.failed("OpenGL context is no longer current on the encoding thread")
    }
    let start = now()
    renderer.beginFrame(width: Int32(viewport.width), height: Int32(viewport.height), bufferScale: 1)
    renderer.render(list, viewport: viewport, bufferScale: 1)
    let encoded = now()
    glFinish()
    let completed = now()
    let error = glGetError()
    guard error == GLenum(GL_NO_ERROR) else { throw BenchmarkError.failed("OpenGL error: \(error)") }
    return (encoded - start, completed - encoded)
  }
}
#endif
