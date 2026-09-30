public struct TextLayout: Equatable, Sendable {
  public struct Line: Equatable, Sendable {
    public let range: Range<Int>
    public let text: String
  }

  public let text: String
  public let lines: [Line]
  public let characterCount: Int

  public init(_ text: String, columns: Int? = nil) {
    if let columns { precondition(columns > 0) }
    self.text = text
    let characters = Array(text)
    characterCount = characters.count
    var lines: [Line] = []
    var start = 0
    for index in characters.indices {
      if characters[index].isNewline {
        lines.append(Line(range: start..<index, text: String(characters[start..<index])))
        start = index + 1
      } else if let columns, index - start == columns {
        lines.append(Line(range: start..<index, text: String(characters[start..<index])))
        start = index
      }
    }
    lines.append(Line(range: start..<characters.count, text: String(characters[start...])))
    self.lines = lines
  }

  public func row(containing offset: Int) -> Int {
    let offset = min(characterCount, max(0, offset))
    return lines.lastIndex(where: { $0.range.lowerBound <= offset }) ?? 0
  }

  public func offset(row: Int, column: Int) -> Int {
    let line = lines[min(lines.count - 1, max(0, row))]
    return line.range.lowerBound + min(line.range.count, max(0, column))
  }

  public func verticalOffset(_ offset: Int, direction: Int) -> Int {
    let row = row(containing: offset)
    let target = row + direction
    if target < 0 { return 0 }
    if target >= lines.count { return characterCount }
    return self.offset(row: target, column: offset - lines[row].range.lowerBound)
  }
}
