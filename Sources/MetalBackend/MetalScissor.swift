import Chroma
import Metal

extension Rect {
  func asMtlScissor(scale: Point) -> MTLScissorRect {
    let values = [
      (minX * scale.x).rounded(.down), (minY * scale.y).rounded(.down),
      (size.width * scale.x).rounded(.up), (size.height * scale.y).rounded(.up),
    ]
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < Float(Int.max) }) else {
      return MTLScissorRect(x: 0, y: 0, width: 0, height: 0)
    }
    return MTLScissorRect(x: Int(values[0]), y: Int(values[1]), width: Int(values[2]), height: Int(values[3]))
  }
}
