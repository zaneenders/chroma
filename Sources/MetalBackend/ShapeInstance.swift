#if METAL_BACKEND

struct ShapeInstance {
  var dst_p0: SIMD2<Float>
  var dst_p1: SIMD2<Float>
  var size: SIMD2<Float>
  var radii: SIMD4<Float>
  var color: SIMD4<Float>
  var borderWidth: Float
  var padding: SIMD3<Float> = .zero
}

#endif
