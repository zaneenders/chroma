import Foundation

public struct ImageID: Hashable, Sendable, Codable {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum ImageResourceError: Error, Equatable, Sendable {
  case invalidDimensions(width: Int, height: Int)
  case pixelCountOverflow
  case invalidByteCount(expected: Int, actual: Int)
  case generationOverflow
}

public struct ImageResource: Equatable, Sendable, Codable {
  public let id: ImageID
  public let generation: UInt64
  public let width: Int
  public let height: Int
  public let rgba8: Data

  public init(
    id: ImageID,
    generation: UInt64 = 0,
    width: Int,
    height: Int,
    rgba8: Data
  ) throws(ImageResourceError) {
    guard width > 0, height > 0 else {
      throw ImageResourceError.invalidDimensions(width: width, height: height)
    }
    let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
    guard !pixelOverflow, !byteOverflow else {
      throw ImageResourceError.pixelCountOverflow
    }
    guard rgba8.count == byteCount else {
      throw ImageResourceError.invalidByteCount(expected: byteCount, actual: rgba8.count)
    }
    self.id = id
    self.generation = generation
    self.width = width
    self.height = height
    self.rgba8 = rgba8
  }

  public func replacingPixels(
    width: Int,
    height: Int,
    rgba8: Data
  ) throws(ImageResourceError) -> ImageResource {
    guard generation < .max else {
      throw ImageResourceError.generationOverflow
    }
    return try ImageResource(
      id: id,
      generation: generation + 1,
      width: width,
      height: height,
      rgba8: rgba8
    )
  }

  public var size: Size {
    Size(width: Float(width), height: Float(height))
  }
}

public enum ImageScaling: Equatable, Sendable, Codable {
  case stretch
  case contain
  case cover

  public func drawRect(
    sourceSize: Size,
    in destination: Rect,
    alignment: ImageAlignment = .center
  ) -> Rect? {
    guard
      sourceSize.width > 0, sourceSize.height > 0,
      destination.size.width > 0, destination.size.height > 0,
      sourceSize.width.isFinite, sourceSize.height.isFinite,
      destination.size.width.isFinite, destination.size.height.isFinite
    else { return nil }

    guard self != .stretch else { return destination }
    let xScale = destination.size.width / sourceSize.width
    let yScale = destination.size.height / sourceSize.height
    let scale = self == .contain ? min(xScale, yScale) : max(xScale, yScale)
    let width = sourceSize.width * scale
    let height = sourceSize.height * scale
    return Rect(
      x: destination.minX + (destination.size.width - width) * alignment.x,
      y: destination.minY + (destination.size.height - height) * alignment.y,
      width: width,
      height: height
    )
  }
}

public struct ImageAlignment: Equatable, Sendable, Codable {
  public let x: Float
  public let y: Float

  public init(x: Float, y: Float) {
    self.x = x.isFinite ? min(1, max(0, x)) : 0.5
    self.y = y.isFinite ? min(1, max(0, y)) : 0.5
  }

  public static let topLeading = ImageAlignment(x: 0, y: 0)
  public static let top = ImageAlignment(x: 0.5, y: 0)
  public static let topTrailing = ImageAlignment(x: 1, y: 0)
  public static let leading = ImageAlignment(x: 0, y: 0.5)
  public static let center = ImageAlignment(x: 0.5, y: 0.5)
  public static let trailing = ImageAlignment(x: 1, y: 0.5)
  public static let bottomLeading = ImageAlignment(x: 0, y: 1)
  public static let bottom = ImageAlignment(x: 0.5, y: 1)
  public static let bottomTrailing = ImageAlignment(x: 1, y: 1)
}

extension ImageResource {
  private enum CodingKeys: String, CodingKey { case id, generation, width, height, rgba8 }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(ImageID.self, forKey: .id),
      generation: values.decode(UInt64.self, forKey: .generation),
      width: values.decode(Int.self, forKey: .width),
      height: values.decode(Int.self, forKey: .height),
      rgba8: values.decode(Data.self, forKey: .rgba8))
  }
}
