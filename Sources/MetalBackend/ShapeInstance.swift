#if METAL_BACKEND

struct ShapeInstance {
  var dst_p0: SIMD2<Float>
  var dst_p1: SIMD2<Float>
  var size: SIMD2<Float>
  // top-left, top-right, bottom-right, bottom-left
  var radii: SIMD4<Float>
  var color: SIMD4<Float>
  var borderWidth: Float
  // x is antialiasing geometry padding; y/z preserve Metal's 16-byte layout.
  var padding: SIMD3<Float> = .zero
}

#endif
