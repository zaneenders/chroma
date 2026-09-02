#if WAYLAND_BACKEND

import Chroma

/// GPU instance consumed by the Wayland OpenGL ES renderer.
struct GLQuad {
  var dst0: (Float, Float)
  var dst1: (Float, Float)
  var uv0: (Float, Float)
  var uv1: (Float, Float)
  var color: (Float, Float, Float, Float)
  var size: (Float, Float) = (0, 0)
  /// Top-left, top-right, bottom-right, bottom-left.
  var radii: (Float, Float, Float, Float) = (0, 0, 0, 0)
  /// Border width, geometry padding, shape flag, RGBA image flag.
  var shape: (Float, Float, Float, Float) = (0, 0, 0, 0)
}

#endif
