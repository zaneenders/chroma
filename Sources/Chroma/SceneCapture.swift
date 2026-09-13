import Foundation

public enum SceneCaptureError: Error, Equatable, Sendable {
  case tooLarge
  case invalidFrame
  case unsupportedVersion(Int)
}

/// A self-contained local snapshot, independent of any rendering backend.
/// Version 3 stores shared images once. Version-2 JSON remains readable;
/// the former remote-wire capture format is not supported.
public enum SceneCapture {
  public static let version = 3
  public static let maximumBytes = 64 * 1024 * 1024

  private struct Header: Decodable {
    let version: Int
  }

  private struct LegacyDocument: Decodable {
    let frame: FrameObservation
  }

  private enum StoredCommand: Codable {
    case drawing(DrawCommand)
    case image(rect: Rect, resource: Int, scaling: ImageScaling, alignment: ImageAlignment)
  }

  private struct Document: Codable {
    let version: Int
    let viewport: Size
    let rasterScale: Point?
    let images: [ImageResource]
    let commands: [StoredCommand]
  }

  // Include pixels as well as identity so conflicting IDs never change a snapshot.
  private struct ImageKey: Hashable {
    let id: ImageID
    let generation: UInt64
    let width: Int
    let height: Int
    let pixels: Data

    init(_ image: ImageResource) {
      id = image.id
      generation = image.generation
      width = image.width
      height = image.height
      pixels = image.rgba8
    }
  }

  public static func encode(_ frame: FrameObservation) throws -> Data {
    try validate(frame)
    var images: [ImageResource] = []
    var indices: [ImageKey: Int] = [:]
    var commands: [StoredCommand] = []
    var imageBytes = 0
    for command in frame.drawList.commands {
      if case .image(let rect, let image, let scaling, let alignment) = command {
        let key = ImageKey(image)
        let index: Int
        if let existing = indices[key] {
          index = existing
        } else {
          // Base64 cannot be smaller than the pixels. Reject oversized unique
          // image storage before allocating its JSON representation.
          guard image.rgba8.count <= maximumBytes - imageBytes else {
            throw SceneCaptureError.tooLarge
          }
          imageBytes += image.rgba8.count
          index = images.count
          images.append(image)
          indices[key] = index
        }
        commands.append(.image(rect: rect, resource: index, scaling: scaling, alignment: alignment))
      } else {
        commands.append(.drawing(command))
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let document = Document(
      version: version, viewport: frame.viewport, rasterScale: frame.rasterScale,
      images: images, commands: commands)
    let data = try encoder.encode(document)
    guard data.count <= maximumBytes else { throw SceneCaptureError.tooLarge }
    return data
  }

  public static func decode(_ data: Data) throws -> FrameObservation {
    guard data.count <= maximumBytes else { throw SceneCaptureError.tooLarge }
    let decoder = JSONDecoder()
    let header = try decoder.decode(Header.self, from: data)
    let frame: FrameObservation
    switch header.version {
    case 2:
      frame = try decoder.decode(LegacyDocument.self, from: data).frame
    case version:
      let document = try decoder.decode(Document.self, from: data)
      let commands = try document.commands.map { stored -> DrawCommand in
        switch stored {
        case .drawing(let command):
          guard case .image = command else { return command }
          throw SceneCaptureError.invalidFrame
        case .image(let rect, let resource, let scaling, let alignment):
          guard document.images.indices.contains(resource) else { throw SceneCaptureError.invalidFrame }
          return .image(rect: rect, image: document.images[resource], scaling: scaling, alignment: alignment)
        }
      }
      frame = FrameObservation(
        drawList: DrawList(commands: commands), viewport: document.viewport, rasterScale: document.rasterScale)
    default:
      throw SceneCaptureError.unsupportedVersion(header.version)
    }
    try validate(frame)
    return frame
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
