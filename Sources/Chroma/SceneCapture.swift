import Foundation

public enum SceneCaptureError: Error, Equatable, Sendable {
  case tooLarge
  case invalidFrame
  case unsupportedVersion(Int)
}

/// A self-contained local snapshot, independent of any rendering backend.
/// Version 2 uses JSON and does not read the former remote-wire capture format.
public enum SceneCapture {
  public static let version = 2
  public static let maximumBytes = 64 * 1024 * 1024

  private struct Document: Codable {
    let version: Int
    let frame: FrameObservation
  }

  public static func encode(_ frame: FrameObservation) throws -> Data {
    try validate(frame)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Document(version: version, frame: frame))
    guard data.count <= maximumBytes else { throw SceneCaptureError.tooLarge }
    return data
  }

  public static func decode(_ data: Data) throws -> FrameObservation {
    guard data.count <= maximumBytes else { throw SceneCaptureError.tooLarge }
    let document = try JSONDecoder().decode(Document.self, from: data)
    guard document.version == version else { throw SceneCaptureError.unsupportedVersion(document.version) }
    try validate(document.frame)
    return document.frame
  }

  private static func validate(_ frame: FrameObservation) throws {
    guard frame.viewport.width.isFinite, frame.viewport.height.isFinite,
      frame.viewport.width > 0, frame.viewport.height > 0
    else { throw SceneCaptureError.invalidFrame }
    if let scale = frame.rasterScale {
      guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else {
        throw SceneCaptureError.invalidFrame
      }
    }
    guard validCommands(viewport: frame.viewport, commands: frame.drawList.commands) else {
      throw SceneCaptureError.invalidFrame
    }
  }

  private static func validCommands(viewport: Size, commands: [DrawCommand]) -> Bool {
    guard (2 / viewport.width).isFinite, (2 / viewport.height).isFinite else { return false }
    var depth = 0
    func point(_ p: Point) -> Bool {
      p.x.isFinite && p.y.isFinite
        && (p.x * (2 / viewport.width)).isFinite
        && (p.y * (2 / viewport.height)).isFinite
    }
    func rect(_ r: Rect) -> Bool {
      r.size.width.isFinite && r.size.height.isFinite && r.size.width >= 0 && r.size.height >= 0
        && point(r.origin) && point(Point(x: r.maxX, y: r.maxY))
    }
    func color(_ c: Color) -> Bool { c.r.isFinite && c.g.isFinite && c.b.isFinite && c.a.isFinite }
    func radii(_ r: CornerRadii) -> Bool {
      [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].allSatisfy { $0.isFinite && $0 >= 0 }
    }
    for command in commands {
      switch command {
      case .fillRect(let r, let c):
        guard rect(r), color(c) else { return false }
      case .strokeRect(let r, let width, let c):
        guard rect(r), width.isFinite, width >= 0, color(c) else { return false }
      case .fillRoundedRect(let r, let corners, let c):
        guard rect(r), radii(corners), color(c) else { return false }
      case .strokeRoundedRect(let r, let corners, let width, let c):
        guard rect(r), radii(corners), width.isFinite, width >= 0, color(c) else { return false }
      case .text(let p, let text, let c, let scale):
        guard point(p), color(c), scale.isFinite, scale > 0 else { return false }
        let metrics = FontMetrics()
        let width = Float(text.count) * metrics.cellAdvance * scale + metrics.glyphWidth * scale
        guard rect(Rect(origin: p, size: Size(width: width, height: metrics.glyphHeight * scale))) else {
          return false
        }
      case .image(let r, let image, let scaling, let alignment):
        guard rect(r), alignment.x.isFinite, alignment.y.isFinite else { return false }
        if r.size.width > 0 && r.size.height > 0 {
          guard let destination = scaling.drawRect(sourceSize: image.size, in: r, alignment: alignment),
            rect(destination)
          else { return false }
        }
      case .pushClip(let r):
        guard rect(r) else { return false }
        depth += 1
      case .popClip:
        guard depth > 0 else { return false }
        depth -= 1
      }
    }
    return depth == 0
  }
}
