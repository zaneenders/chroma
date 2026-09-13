import Chroma
import Foundation

public struct RenderFixture: Sendable {
  public static let version = 2
  public static let names = ["shapes", "text", "clipped", "images"] + TranscriptReplay.names
  public let viewport = Size(width: 1100, height: 720)
  public let sequence: [DrawList]
  public var list: DrawList { sequence[0] }

  public init(name: String, count: Int) throws {
    precondition(Self.names.contains(name) && count > 0)
    if TranscriptReplay.names.contains(name) {
      sequence = TranscriptReplay.make(name: name, historyLines: count)
      return
    }
    var list = DrawList()
    var pixels = Data()
    for y in 0..<64 {
      for x in 0..<64 {
        let value: UInt8 = (x / 8 + y / 8) % 2 == 0 ? 0 : 255
        pixels.append(contentsOf: [value, value, value, 255])
      }
    }
    let image = try ImageResource(
      id: ImageID("benchmark.checker"), width: 64, height: 64, rgba8: pixels)
    if name == "clipped" { list.pushClip(Rect(x: 0, y: 0, width: 550, height: 360)) }
    for index in 0..<count {
      let x = Float((index * 37) % 1080)
      let y = Float((index * 53) % 700)
      let rect = Rect(x: x, y: y, width: 18, height: 18)
      switch name {
      case "text":
        list.text("Row \(index % 128): Chroma render replay", at: Point(x: x, y: y), color: .white, scale: 0.5)
      case "images": list.image(image, in: rect)
      default:
        list.fillRoundedRect(rect, radius: 4, color: Color(r: Float(index % 10) / 10, g: 0.5, b: 0.8, a: 1))
      }
    }
    if name == "clipped" { list.popClip() }
    self.sequence = [list]
  }
}
