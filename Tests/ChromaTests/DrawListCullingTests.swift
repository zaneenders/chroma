import Chroma
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
}
