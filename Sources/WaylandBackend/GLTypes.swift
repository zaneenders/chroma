#if WAYLAND_BACKEND

import Chroma

/// GPU instance consumed by the Wayland OpenGL ES renderer.
struct GLQuad {
  var dst0: (Float, Float)
  var dst1: (Float, Float)
  var uv0: (Float, Float)
  var uv1: (Float, Float)
  var color: (Float, Float, Float, Float)
}

#endif
