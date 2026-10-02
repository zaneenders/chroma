#!/usr/bin/env swift
import Foundation

struct MipLevel {
  let width: Int
  let height: Int
  var pixels: [UInt8]
}

struct Texel: Hashable {
  let x: Int
  let y: Int
}

func insidePolygon(_ x: Double, _ y: Double, _ points: [(Double, Double)]) -> Bool {
  var inside = false
  for index in points.indices {
    let (ax, ay) = points[index]
    let (bx, by) = points[(index + 1) % points.count]
    if (ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax {
      inside.toggle()
    }
  }
  return inside
}

func approximatelyEqual(_ x: Double, _ y: Double) -> Bool {
  (1...11).contains(x)
    && [12.0, 16.0].contains {
      abs(y - ($0 + sin((x - 1) * .pi / 5))) < 0.65
    }
}

func heavyBallotX(_ x: Double, _ y: Double) -> Bool {
  (2...10).contains(x) && (9...19).contains(y)
    && min(abs(y - x - 4), abs(y + x - 16)) < 1.5
}

func thumbsUp(_ x: Double, _ y: Double) -> Bool {
  let outline: [(Double, Double)] = [
    (3, 12), (5, 9), (5, 5), (6, 4), (7, 4), (8, 6), (8, 10),
    (10, 10), (11, 11), (11, 17), (10, 20), (9, 21), (3, 21),
  ]
  return insidePolygon(x, y, outline) || ((1...2.5).contains(x) && (12...21).contains(y))
}

let atlasURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("Sources/ChromaFont/Resources/FontAtlas.atlas")
let data = try Data(contentsOf: atlasURL)
var offset = 0
func readWord() -> UInt32 {
  precondition(offset + 4 <= data.count, "Truncated atlas header")
  defer { offset += 4 }
  return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
}
let magic = readWord()
let version = readWord()
let width = Int(readWord())
let height = Int(readWord())
let count = Int(readWord())
precondition(width > 0 && height > 0 && count <= (data.count - offset) / 4, "Invalid atlas dimensions or count")
var scalars = (0..<count).map { _ in readWord() }
var levels: [MipLevel] = []
var w = width
var h = height
while true {
  precondition(w <= (data.count - offset) / h, "Truncated atlas pixels")
  levels.append(MipLevel(width: w, height: h, pixels: Array(data[offset..<(offset + w * h)])))
  offset += w * h
  if w == 1 && h == 1 { break }
  w = max(1, w / 2)
  h = max(1, h / 2)
}
precondition(offset == data.count, "Unexpected trailing atlas data")

var changed: Set<Texel> = []
let glyphs: [(UInt32, (Double, Double) -> Bool)] = [
  (0x2248, approximatelyEqual), (0x1F44D, thumbsUp), (0x2718, heavyBallotX),
]
for (scalar, shape) in glyphs {
  if !scalars.contains(scalar) { scalars.append(scalar) }
  let index = scalars.firstIndex(of: scalar)!
  precondition(width >= 32 * 66 && index < (height / 90) * 32, "Atlas has no room for glyph")
  let originX = (index % 32) * 66 + 3
  let originY = (index / 32) * 90 + 3
  for y in 0..<84 {
    for x in 0..<60 {
      var coverage = 0
      for sy in 0..<4 {
        for sx in 0..<4 {
          if shape(
            (Double(x) + (Double(sx) + 0.5) / 4) / 3,
            (Double(y) + (Double(sy) + 0.5) / 4) / 3)
          {
            coverage += 1
          }
        }
      }
      levels[0].pixels[(originY + y) * width + originX + x] = UInt8((coverage * 255 + 8) / 16)
      changed.insert(Texel(x: originX + x, y: originY + y))
    }
  }
}

// Preserve existing glyphs and mip coverage by updating only affected texels.
for index in 1..<levels.count {
  let parent = levels[index - 1]
  let width = levels[index].width
  let height = levels[index].height
  changed = Set(
    changed.map { Texel(x: $0.x / 2, y: $0.y / 2) }
      .filter { $0.x < width && $0.y < height })
  for texel in changed {
    var sum = 0
    for dy in 0..<2 {
      for dx in 0..<2 {
        sum += Int(
          parent.pixels[
            min(parent.height - 1, 2 * texel.y + dy) * parent.width
              + min(parent.width - 1, 2 * texel.x + dx)])
      }
    }
    levels[index].pixels[texel.y * width + texel.x] = UInt8((sum + 2) / 4)
  }
}

var output = Data()
for word in [magic, version, UInt32(width), UInt32(height), UInt32(scalars.count)] + scalars {
  for shift in stride(from: 0, to: 32, by: 8) {
    output.append(UInt8(truncatingIfNeeded: word >> shift))
  }
}
for level in levels { output.append(contentsOf: level.pixels) }
try output.write(to: atlasURL, options: .atomic)
