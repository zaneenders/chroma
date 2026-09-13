#if WAYLAND_BACKEND

import Chroma

struct GLQuad {
  var dst0: (Float, Float)
  var dst1: (Float, Float)
  var uv0: (Float, Float)
  var uv1: (Float, Float)
  var color: (Float, Float, Float, Float)
  var size: (Float, Float) = (0, 0)
  var radii: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var shape: (Float, Float, Float, Float) = (0, 0, 0, 0)
}

#endif
