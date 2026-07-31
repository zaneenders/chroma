#if METAL_BACKEND
  import func Foundation.ceil
#endif

struct GUIVertex {
  var position: SIMD2<Float>
  var uv: SIMD2<Float>
  var color: SIMD4<Float>
}
