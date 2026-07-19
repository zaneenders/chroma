/// A vertex for the solid-color pipeline, matching the `GUIVertex` struct in the Metal shader.
#if METAL_BACKEND
  import func Foundation.ceil
#endif

struct GUIVertex {
  var position: SIMD2<Float>  // NDC
  var uv: SIMD2<Float>        // reserved for textured quads, (0,0) for solids
  var color: SIMD4<Float>
}
