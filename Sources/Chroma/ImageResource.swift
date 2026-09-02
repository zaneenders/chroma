import Foundation

public struct ImageID: Hashable, Sendable {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum ImageResourceError: Error, Equatable, Sendable {
  case invalidDimensions(width: Int, height: Int)
  case pixelCountOverflow
  case invalidByteCount(expected: Int, actual: Int)
}

/// A backend-independent, tightly packed RGBA8 image.
///
/// Pixels are stored top-to-bottom as straight-alpha red, green, blue, and
/// alpha bytes. Image decoding and color-profile conversion are intentionally
/// left to the application.
public struct ImageResource: Equatable, Sendable {
  public var id: ImageID
  public var generation: UInt64
  public var width: Int
  public var height: Int
  public var rgba8: Data

  public init(
    id: ImageID,
    generation: UInt64 = 0,
    width: Int,
    height: Int,
    rgba8: Data
  ) throws {
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

  public var size: Size {
    Size(width: Float(width), height: Float(height))
  }
}

public enum ImageContentMode: Equatable, Sendable {
  case stretch
  case aspectFit
  case aspectFill

  /// Resolves the textured quad inside `destination`. Aspect-fill can return a
  /// quad larger than the destination and must therefore be clipped to it.
  public func drawRect(sourceSize: Size, in destination: Rect) -> Rect? {
    guard
      sourceSize.width > 0, sourceSize.height > 0,
      destination.size.width > 0, destination.size.height > 0,
      sourceSize.width.isFinite, sourceSize.height.isFinite,
      destination.size.width.isFinite, destination.size.height.isFinite
    else { return nil }

    guard self != .stretch else { return destination }
    let xScale = destination.size.width / sourceSize.width
    let yScale = destination.size.height / sourceSize.height
    let scale = self == .aspectFit ? min(xScale, yScale) : max(xScale, yScale)
    let width = sourceSize.width * scale
    let height = sourceSize.height * scale
    return Rect(
      x: destination.minX + (destination.size.width - width) / 2,
      y: destination.minY + (destination.size.height - height) / 2,
      width: width,
      height: height
    )
  }
}
