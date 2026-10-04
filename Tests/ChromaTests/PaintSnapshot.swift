import Chroma
import ChromaFont
import ChromaTesting

enum PaintSnapshotEntry: Equatable {
  case fillRect(rect: Rect, color: Color)
  case strokeRect(rect: Rect, width: Float, color: Color)
  case fillRoundedRect(rect: Rect, radii: CornerRadii, color: Color)
  case strokeRoundedRect(rect: Rect, radii: CornerRadii, width: Float, color: Color)
  case text(position: Point, text: String, color: Color, scale: Float)
  case quad(DrawQuad)
  case pushClip(Rect)
  case popClip

  static func image(rect: Rect, image: ImageResource, scaling: ImageScaling, alignment: ImageAlignment) -> Self {
    var list = DrawList()
    list.image(image, in: rect, scaling: scaling, alignment: alignment)
    guard case .quad(let quad) = list.commands[0] else { preconditionFailure() }
    return .quad(quad)
  }
}

private struct GlyphCoordinates: Hashable {
  var x: Float
  var y: Float
}

private let glyphCharacters: [GlyphCoordinates: String] = {
  let atlas = HighResolutionFontAtlas()
  var result: [GlyphCoordinates: String] = [:]
  for scalar in atlas.characterIndices.keys {
    let character = Character(String(UnicodeScalar(scalar)!))
    let (x, y, _, _) = atlas.glyphUV(character)
    result[GlyphCoordinates(x: x, y: y)] = String(character)
  }
  return result
}()

private func paintSnapshot(_ entries: [DrawEntry]) -> [PaintSnapshotEntry] {
  var result: [PaintSnapshotEntry] = []
  for entry in entries {
    switch entry {
    case .pushClip(let rect): result.append(.pushClip(rect))
    case .popClip: result.append(.popClip)
    case .quad(let quad):
      let color = quad.colors.topLeft
      if quad.texture == .fontAtlas {
        let character = glyphCharacters[GlyphCoordinates(x: quad.sourceRect.minX, y: quad.sourceRect.minY)] ?? "�"
        let scale = quad.rect.size.height / FontMetrics().glyphHeight
        if case .text(let position, let text, let previousColor, let previousScale) = result.last,
          previousColor == color, previousScale == scale,
          position.y == quad.rect.minY,
          abs(position.x + Float(text.count) * FontMetrics().cellAdvance * scale - quad.rect.minX) < 0.001
        {
          result[result.count - 1] = .text(position: position, text: text + character, color: color, scale: scale)
        } else {
          result.append(.text(position: quad.rect.origin, text: character, color: color, scale: scale))
        }
      } else if quad.texture != .white {
        result.append(.quad(quad))
      } else if quad.borderThickness != 0 {
        if quad.radii == .zero {
          result.append(.strokeRect(rect: quad.rect, width: quad.borderThickness, color: color))
        } else {
          result.append(
            .strokeRoundedRect(rect: quad.rect, radii: quad.radii, width: quad.borderThickness, color: color))
        }
      } else if quad.radii == .zero {
        result.append(.fillRect(rect: quad.rect, color: color))
      } else {
        result.append(.fillRoundedRect(rect: quad.rect, radii: quad.radii, color: color))
      }
    }
  }
  return result
}

extension DrawList {
  var paintSnapshot: [PaintSnapshotEntry] { ChromaTests.paintSnapshot(commands) }
}
extension HeadlessFrame {
  var paintSnapshot: [PaintSnapshotEntry] { ChromaTests.paintSnapshot(commands) }
}
