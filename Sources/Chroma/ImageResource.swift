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

/// How image pixels are scaled within the rectangle assigned by layout.
public enum ImageScaling: Equatable, Sendable {
  /// Distort the image to exactly match the destination rectangle.
  case stretch
  /// Preserve aspect ratio while keeping the entire image visible.
  case contain
  /// Preserve aspect ratio while covering the destination, cropping overflow.
  case cover

  /// Resolves the textured quad inside `destination`. Cover can return a quad
  /// larger than the destination and must therefore be clipped to it.
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

/// Positions a scaled image within its destination rectangle.
///
/// Components use normalized coordinates and are clamped to `0...1`. For
/// example, `(0, 0)` preserves the top-leading region when an image is cropped,
/// while `(1, 1)` preserves the bottom-trailing region.
public struct ImageAlignment: Equatable, Sendable {
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
