import Chroma
import Foundation
import Testing

struct DrawListCullingTests {
  @Test func cullingRetainsNestedClipSemanticsAndPainterOrder() {
    let visible = DrawEntry.quad(DrawQuad(rect: Rect(x: 2, y: 2, width: 3, height: 3)))
    let hidden = DrawEntry.quad(DrawQuad(rect: Rect(x: 50, y: 50, width: 3, height: 3)))
    let clip = DrawEntry.pushClip(Rect(x: 0, y: 0, width: 10, height: 10))
    let commands: [DrawEntry] = [
      clip, visible, hidden,
      .pushClip(Rect(x: 30, y: 30, width: 10, height: 10)), hidden, .popClip, visible, .popClip, hidden,
    ]
    #expect(
      DrawList(commands: commands).culled(to: Size(width: 100, height: 100)).commands == [
        clip, visible, commands[3], .popClip, visible, .popClip, hidden,
      ])
  }

  @Test func glyphOverhangAndAntialiasFringeArePreserved() {
    let commands: [DrawEntry] = [
      .quad(DrawQuad(rect: Rect(x: -10, y: 0, width: 9.5, height: 5))),
      .quad(DrawQuad(rect: Rect(x: -15, y: 0, width: 20, height: 28), texture: .fontAtlas)),
      .quad(DrawQuad(rect: Rect(x: 200, y: 0, width: 10, height: 10))),
    ]
    #expect(
      DrawList(commands: commands).culled(to: Size(width: 100, height: 100)).commands == Array(commands.prefix(2)))
  }

  @Test func onePassPreservesTheSameTexturedCommandsAsHostAndRendererCulling() throws {
    let viewport = Size(width: 100, height: 100)
    let image = try ImageResource(
      id: ImageID("culling"), width: 1, height: 1, rgba8: Data([255, 0, 0, 128]))
    let imageQuad = DrawEntry.quad(
      DrawQuad(
        rect: Rect(x: 5, y: 5, width: 10, height: 10),
        sourceRect: Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        texture: .image(image), radii: CornerRadii(3), borderThickness: 2))
    let fringe = DrawEntry.quad(
      DrawQuad(rect: Rect(x: -8, y: 10, width: 4, height: 4), edgeSoftness: 5))
    let glyph = DrawEntry.quad(
      DrawQuad(rect: Rect(x: 8, y: 8, width: 12, height: 16), texture: .fontAtlas))
    let hidden = DrawEntry.quad(DrawQuad(rect: Rect(x: 200, y: 0, width: 10, height: 10)))
    let outer = DrawEntry.pushClip(Rect(x: 0, y: 0, width: 30, height: 30))
    let empty = DrawEntry.pushClip(Rect(x: 50, y: 50, width: 10, height: 10))
    let source = DrawList(commands: [
      hidden, fringe, outer, imageQuad, glyph, empty, imageQuad, .popClip,
      imageQuad, .popClip, hidden, glyph,
    ])
    let once = source.culled(to: viewport)
    #expect(
      once.commands == [
        fringe, outer, imageQuad, glyph, empty, .popClip, imageQuad, .popClip, glyph,
      ])
    #expect(once.commands == once.culled(to: viewport).commands)
    #expect(source.commands.count == 12)
  }
}
