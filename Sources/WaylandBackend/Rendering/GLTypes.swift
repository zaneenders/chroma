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
  var topRight: (Float, Float, Float, Float)
  var bottomRight: (Float, Float, Float, Float)
  var bottomLeft: (Float, Float, Float, Float)
}

// Resource identity, not pixel equality: avoid comparing entire image payloads on the hot path.
enum GLTextureKey: Equatable {
  case white
  case fontAtlas
  case image(ImageID, UInt64, Int, Int)

  init(_ texture: TextureResource) {
    switch texture {
    case .white: self = .white
    case .fontAtlas: self = .fontAtlas
    case .image(let image): self = .image(image.id, image.generation, image.width, image.height)
    }
  }
}

extension GLQuad {
  init(_ input: DrawQuad) {
    let rect = input.rect
    let padding = max(1, input.edgeSoftness)
    let radii = input.radii.normalized(for: rect.size)
    let uv = input.sourceRect
    func color(_ color: Color) -> (Float, Float, Float, Float) { (color.r, color.g, color.b, color.a) }
    self.init(
      dst0: (rect.minX - padding, rect.minY - padding),
      dst1: (rect.maxX + padding, rect.maxY + padding),
      uv0: (uv.minX, uv.minY), uv1: (uv.maxX, uv.maxY),
      color: color(input.colors.topLeft),
      size: (rect.size.width, rect.size.height),
      radii: (radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft),
      shape: (
        max(0, input.borderThickness), padding, max(0, input.edgeSoftness),
        input.texture == .fontAtlas ? 1 : 0
      ),
      topRight: color(input.colors.topRight), bottomRight: color(input.colors.bottomRight),
      bottomLeft: color(input.colors.bottomLeft))
  }
}
