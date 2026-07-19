/// One glyph quad in the text instance buffer.
private struct TextInstance {
  var dst_p0: SIMD2<Float>  // top-left in NDC
  var dst_p1: SIMD2<Float>  // bottom-right in NDC
  var tex_tl: SIMD2<Float>  // font atlas UV of the glyph's top-left
  var tex_br: SIMD2<Float>  // font atlas UV of the glyph's bottom-right
  var color: SIMD4<Float>
}
