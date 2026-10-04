import Chroma
import ChromaFont
import Foundation
import Testing

struct DrawQuadTests {
  @Test func composableQuadRoundTripsWithoutLosingParameters() throws {
    let image = try ImageResource(
      id: ImageID("tile"), width: 1, height: 1,
      rgba8: Data([10, 20, 30, 255]))
    let quad = DrawQuad(
      rect: Rect(x: 5, y: 6, width: 40, height: 30),
      sourceRect: Rect(x: 0.2, y: 0.3, width: 0.4, height: 0.5), texture: .image(image),
      colors: CornerColors(topLeft: .white, topRight: .black, bottomRight: .yellow, bottomLeft: .white),
      radii: CornerRadii(4), borderThickness: 2, edgeSoftness: 3)
    var list = DrawList()
    list.pushClip(quad.rect)
    list.append(quad)
    list.popClip()
    let decoded = try JSONDecoder().decode(DrawList.self, from: JSONEncoder().encode(list))
    #expect(decoded.commands == list.commands)
    #expect(decoded.commands == [.pushClip(quad.rect), .quad(quad), .popClip])
  }

  @Test func textIsLoweredToGlyphQuadsWithAtlasCoordinates() {
    var list = DrawList()
    list.text("ab", at: Point(x: 3, y: 4), color: .yellow, scale: 2)
    #expect(list.commands.count == 2)
    let atlas = HighResolutionFontAtlas()
    for (index, character) in Array("ab").enumerated() {
      guard case .quad(let quad) = list.commands[index] else {
        Issue.record("Expected a glyph quad")
        return
      }
      let (x, y, x1, y1) = atlas.glyphUV(character)
      #expect(quad.texture == .fontAtlas)
      #expect(quad.rect == Rect(x: 3 + Float(index) * 24, y: 4, width: 40, height: 56))
      #expect(quad.sourceRect == Rect(x: x, y: y, width: x1 - x, height: y1 - y))
      #expect(quad.colors == CornerColors(.yellow))
    }
  }

  @Test func imageCoverCropsTextureCoordinatesBeforeSubmission() throws {
    let image = try ImageResource(
      id: ImageID("wide"), width: 2, height: 1,
      rgba8: Data(repeating: 255, count: 8))
    var list = DrawList()
    let rect = Rect(x: 10, y: 20, width: 50, height: 50)
    list.image(image, in: rect, scaling: .cover)
    #expect(
      list.commands == [
        .quad(
          DrawQuad(
            rect: rect, sourceRect: Rect(x: 0.25, y: 0, width: 0.5, height: 1), texture: .image(image)))
      ])
  }

  @Test func softnessExtendsCullingBounds() {
    let quad = DrawQuad(rect: Rect(x: -8, y: 10, width: 4, height: 4), edgeSoftness: 5)
    #expect(DrawList(commands: [.quad(quad)]).culled(to: Size(width: 30, height: 30)).commands == [.quad(quad)])
  }
}
