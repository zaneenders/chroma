#if WAYLAND_BACKEND

import CEGL
import CWaylandClient
import CWaylandEGL

/// Owns the EGL display, context, surface, and native Wayland EGL window.
///
/// `cleanup()` is idempotent. OpenGL resources must be released before calling
/// it because this object clears the current context before destroying it.
@MainActor
final class EGLWindowContext {
  private var display: EGLDisplay?
  private var context: EGLContext?
  private var surface: EGLSurface?
  private var window: OpaquePointer?

  var isReady: Bool { display != nil && context != nil && surface != nil && window != nil }

  func setUp(
    display waylandDisplay: OpaquePointer,
    surface waylandSurface: OpaquePointer,
    width: Int32,
    height: Int32,
    bufferScale: Int32
  ) throws {
    cleanup()

    display = unsafe eglGetDisplay(EGLNativeDisplayType(waylandDisplay))
    guard display != nil, unsafe eglInitialize(display, nil, nil) == EGL_TRUE else {
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
      _ = unsafe eglChooseConfig(display, $0.baseAddress, &config, 1, &count)
    }
    guard count > 0, config != nil else { throw WaylandError("no EGL ES3 window config") }

    var contextAttributes: [EGLint] = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE]
    context = contextAttributes.withUnsafeMutableBufferPointer {
      unsafe eglCreateContext(display, config, nil, $0.baseAddress)
    }
    guard context != nil else { throw WaylandError("eglCreateContext failed") }

    unsafe wl_surface_set_buffer_scale(waylandSurface, bufferScale)
    window = unsafe wl_egl_window_create(
      waylandSurface, width * bufferScale, height * bufferScale)
    guard let window else { throw WaylandError("wl_egl_window_create failed") }
    surface = unsafe eglCreateWindowSurface(
      display, config, EGLNativeWindowType(bitPattern: window), nil)
    guard surface != nil else { throw WaylandError("eglCreateWindowSurface failed") }
    guard unsafe eglMakeCurrent(display, surface, surface, context) == EGL_TRUE else {
      throw WaylandError("eglMakeCurrent failed")
    }
    _ = unsafe eglSwapInterval(display, 1)
  }

  func resize(width: Int32, height: Int32, bufferScale: Int32) {
    guard let window else { return }
    unsafe wl_egl_window_resize(
      window, width * bufferScale, height * bufferScale, 0, 0)
  }

  func swapBuffers() {
    guard let display, let surface else { return }
    _ = unsafe eglSwapBuffers(display, surface)
  }

  func cleanup() {
    if let display {
      _ = unsafe eglMakeCurrent(display, nil, nil, nil)
      if let surface { _ = unsafe eglDestroySurface(display, surface) }
      if let context { _ = unsafe eglDestroyContext(display, context) }
      _ = unsafe eglTerminate(display)
    }
    if let window { unsafe wl_egl_window_destroy(window) }
    surface = nil
    context = nil
    display = nil
    self.window = nil
  }
}

#endif
