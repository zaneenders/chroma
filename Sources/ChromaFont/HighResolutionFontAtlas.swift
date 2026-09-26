import Foundation

public struct FontAtlasMipLevel: Sendable {
  public let width: Int
  public let height: Int
  public let pixels: [UInt8]

  public init(width: Int, height: Int, pixels: [UInt8]) {
    self.width = width
    self.height = height
    self.pixels = pixels
  }
}

public struct HighResolutionFontAtlas: Sendable {
  public static let scale = 3
  public static let columns = 32
  public static let sourceGlyphWidth = 20
  public static let sourceGlyphHeight = 28
  public static let padding = scale

  private static let bundled: HighResolutionFontAtlas = {
    do {
      guard let url = Bundle.module.url(forResource: "FontAtlas", withExtension: "atlas", subdirectory: "Resources")
      else {
        preconditionFailure("Missing ChromaFont resource bundle")
      }
      return try HighResolutionFontAtlas(data: Data(contentsOf: url))
    } catch {
      preconditionFailure("Invalid bundled font atlas: \(error)")
    }
  }()

  public let characterIndices: [UInt32: Int]
  private let indices: [Character: Int]
  private let levels: [FontAtlasMipLevel]
  private let fallback: Int

  public var width: Int { levels[0].width }
  public var height: Int { levels[0].height }
  public var pixels: [UInt8] { levels[0].pixels }
  public var glyphWidth: Int { Self.sourceGlyphWidth * Self.scale }
  public var glyphHeight: Int { Self.sourceGlyphHeight * Self.scale }
  public var cellWidth: Int { glyphWidth + 2 * Self.padding }
  public var cellHeight: Int { glyphHeight + 2 * Self.padding }

  public init() { self = Self.bundled }

  enum AssetError: Error { case invalidAtlas }

  init(data: Data) throws(AssetError) {
    self = try Self(bytes: data.bytes)
  }

  private static func word(_ bytes: RawSpan, cursor: inout Int) throws(AssetError) -> UInt32 {
    guard bytes.byteCount - cursor >= 4 else { throw AssetError.invalidAtlas }
    defer { cursor += 4 }
    return bytes.load(fromByteOffset: cursor, as: UInt32.self, .littleEndian)
  }

  private init(bytes: RawSpan) throws(AssetError) {
    var cursor = 0
    guard try Self.word(bytes, cursor: &cursor) == 0x4C54_4143,
      try Self.word(bytes, cursor: &cursor) == 1
    else { throw AssetError.invalidAtlas }
    let width = Int(try Self.word(bytes, cursor: &cursor))
    let height = Int(try Self.word(bytes, cursor: &cursor))
    let count = Int(try Self.word(bytes, cursor: &cursor))
    let cellHeight = Self.sourceGlyphHeight * Self.scale + 2 * Self.padding
    guard width == Self.columns * (Self.sourceGlyphWidth * Self.scale + 2 * Self.padding),
      height > 0, height <= 4096, height % cellHeight == 0,
      count > 0, count <= (height / cellHeight) * Self.columns
    else { throw AssetError.invalidAtlas }
    var scalars: [UInt32] = []
    for _ in 0..<count { scalars.append(try Self.word(bytes, cursor: &cursor)) }
    var levels: [FontAtlasMipLevel] = []
    var w = width
    var h = height
    while true {
      let size = w * h
      guard bytes.byteCount - cursor >= size else { throw AssetError.invalidAtlas }
      let input = Span<UInt8>(viewing: bytes.extracting(cursor..<(cursor + size)))
      let pixels = [UInt8](capacity: size) { output in
        for index in input.indices { output.append(input[index]) }
      }
      levels.append(FontAtlasMipLevel(width: w, height: h, pixels: pixels))
      cursor += size
      if w == 1 && h == 1 { break }
      w = max(1, w / 2)
      h = max(1, h / 2)
    }
    guard cursor == bytes.byteCount else { throw AssetError.invalidAtlas }
    var indices: [Character: Int] = [:]
    var scalarIndices: [UInt32: Int] = [:]
    for (index, value) in scalars.enumerated() {
      guard let scalar = UnicodeScalar(value) else { throw AssetError.invalidAtlas }
      let character = Character(String(scalar))
      guard indices.updateValue(index, forKey: character) == nil else { throw AssetError.invalidAtlas }
      scalarIndices[value] = index
    }
    guard let fallback = scalarIndices[0xFFFD] else { throw AssetError.invalidAtlas }
    self.indices = indices
    characterIndices = scalarIndices
    self.levels = levels
    self.fallback = fallback
  }

  public func mipLevels() -> [FontAtlasMipLevel] { levels }

  public func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    let index = indices[character] ?? fallback
    let x = (index % Self.columns) * cellWidth + Self.padding
    let y = (index / Self.columns) * cellHeight + Self.padding
    return (
      Float(x) / Float(width), Float(y) / Float(height),
      Float(x + glyphWidth) / Float(width), Float(y + glyphHeight) / Float(height)
    )
  }
}
