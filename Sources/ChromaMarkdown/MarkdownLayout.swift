import Chroma
import Foundation

enum MarkdownBlock: Equatable, Sendable {
  case paragraph(String)
  case code(language: String?, code: String)
  case heading(level: Int, text: String)
  case listItem(marker: String, text: String, depth: Int)
  case quote(String)
  case rule
}

func segmentMarkdown(_ source: String) -> [MarkdownBlock] {
  var blocks: [MarkdownBlock] = []
  var inCode = false
  var codeLanguage: String? = nil
  var codeLines: [String] = []
  var paragraphLines: [String] = []

  func flushParagraph() {
    guard !paragraphLines.isEmpty else { return }
    blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
    paragraphLines = []
  }

  for line in source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(
    separator: "\n", omittingEmptySubsequences: false)
  {
    let s = String(line)
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") {
      if inCode {
        blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        inCode = false
        codeLanguage = nil
        codeLines = []
      } else {
        flushParagraph()
        inCode = true
        let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        codeLanguage = lang.isEmpty ? nil : lang
      }
      continue
    }
    if inCode {
      codeLines.append(s)
      continue
    }
    if trimmed.isEmpty {
      flushParagraph()
      continue
    }
    if trimmed == "---" || trimmed == "***" || trimmed == "___" {
      flushParagraph()
      blocks.append(.rule)
      continue
    }
    var level = 0
    while level < trimmed.count && level < 6 && trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == "#" {
      level += 1
    }
    if level > 0,
      trimmed.count > level,
      trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " "
    {
      flushParagraph()
      blocks.append(
        .heading(level: level, text: String(trimmed.dropFirst(level + 1))))
      continue
    }
    if trimmed.hasPrefix("> ") {
      flushParagraph()
      blocks.append(.quote(String(trimmed.dropFirst(2))))
      continue
    }
    if let item = markdownListItem(in: s) {
      flushParagraph()
      blocks.append(item)
      continue
    }
    paragraphLines.append(s)
  }
  flushParagraph()
  if inCode {
    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
  }
  return blocks
}

private func markdownListItem(in line: String) -> MarkdownBlock? {
  let indentation = line.prefix { $0 == " " }.count
  let trimmed = line.dropFirst(indentation)
  if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
    return .listItem(marker: "•", text: String(trimmed.dropFirst(2)), depth: indentation / 2)
  }

  let digits = trimmed.prefix { $0.isNumber }
  guard !digits.isEmpty else { return nil }
  let suffix = trimmed.dropFirst(digits.count)
  guard suffix.hasPrefix(". ") || suffix.hasPrefix(") ") else { return nil }
  return .listItem(
    marker: "\(digits).", text: String(suffix.dropFirst(2)), depth: indentation / 2)
}

struct MarkdownRun: Equatable, Sendable {
  var text: String
  var code: Bool = false
  var bold: Bool = false
}

func inlineRuns(_ text: String) -> [MarkdownRun] {
  var runs: [MarkdownRun] = []

  func appendBoldAware(_ text: Substring, code: Bool) {
    var rest = text
    while let open = rest.range(of: "**") {
      let plain = rest[..<open.lowerBound]
      if !plain.isEmpty { runs.append(MarkdownRun(text: String(plain), code: code)) }
      let after = rest[open.upperBound...]
      guard let close = after.range(of: "**") else {
        runs.append(MarkdownRun(text: String(rest[open.lowerBound...]), code: code))
        return
      }
      runs.append(MarkdownRun(text: String(after[..<close.lowerBound]), code: code, bold: true))
      rest = after[close.upperBound...]
    }
    if !rest.isEmpty { runs.append(MarkdownRun(text: String(rest), code: code)) }
  }

  var rest = Substring(text)
  while let tick = rest.firstIndex(of: "`") {
    appendBoldAware(rest[..<tick], code: false)
    let after = rest.index(after: tick)
    guard let close = rest[after...].firstIndex(of: "`") else {
      appendBoldAware(rest[tick...], code: false)
      return runs
    }
    runs.append(MarkdownRun(text: String(rest[after..<close]), code: true))
    rest = rest[rest.index(after: close)...]
  }
  appendBoldAware(rest, code: false)
  return runs
}

enum VisualLineKind: Equatable {
  case plain
  case heading
  case code
}

struct VisualRun: Equatable {
  var text: String
  var color: Color
}

struct VisualLine: Equatable {
  var kind: VisualLineKind = .plain
  var runs: [VisualRun] = []
  var columnCount: Int = 0
  var trailingText: String = "\n"
}

func layoutMarkdown(
  _ blocks: [MarkdownBlock],
  columns: Int,
  theme: ChromaTheme,
  baseColor: Color
) -> [VisualLine] {
  let columns = max(1, columns)
  var lines: [VisualLine] = []

  func wrapRuns(_ runs: [MarkdownRun], colorFor: (MarkdownRun) -> Color, kind: VisualLineKind) {
    var line = VisualLine(kind: kind)
    func emit(trailingText: String = "") {
      line.trailingText = trailingText
      lines.append(line)
      line = VisualLine(kind: kind)
    }
    for run in runs {
      let color = colorFor(run)
      var word = ""
      func flushWord() {
        guard !word.isEmpty else { return }
        var remaining = word
        word = ""
        while !remaining.isEmpty {
          if line.columnCount + remaining.count <= columns {
            line.runs.append(VisualRun(text: remaining, color: color))
            line.columnCount += remaining.count
            remaining = ""
          } else if remaining.count > columns {
            let room = columns - line.columnCount
            if room > 0 {
              let cut = remaining.index(remaining.startIndex, offsetBy: room)
              line.runs.append(VisualRun(text: String(remaining[..<cut]), color: color))
              line.columnCount += room
              remaining = String(remaining[cut...])
            }
            emit()
          } else {
            emit()
          }
        }
      }
      for ch in run.text {
        if ch == "\n" {
          flushWord()
          emit(trailingText: "\n")
        } else if ch == " " {
          flushWord()
          if line.columnCount >= columns { emit(trailingText: " ") }
          if line.columnCount > 0 {
            line.runs.append(VisualRun(text: " ", color: color))
            line.columnCount += 1
          }
        } else {
          word.append(ch)
        }
      }
      flushWord()
    }
    if line.columnCount > 0 || lines.isEmpty { emit() }
  }

  var previousWasListItem = false
  for (index, block) in blocks.enumerated() {
    let isListItem: Bool
    if case .listItem = block { isListItem = true } else { isListItem = false }
    if index > 0 {
      if !lines.isEmpty { lines[lines.count - 1].trailingText = "\n" }
      if !(isListItem && previousWasListItem) {
        lines.append(VisualLine(trailingText: "\n"))
      }
    }

    switch block {
    case .paragraph(let text):
      wrapRuns(
        inlineRuns(text),
        colorFor: { run in
          run.code ? theme.warning : run.bold ? theme.foreground : baseColor
        }, kind: .plain)
    case .heading(let level, let text):
      let prefix = String(repeating: "#", count: level) + " "
      wrapRuns(
        [MarkdownRun(text: prefix), MarkdownRun(text: text, bold: true)],
        colorFor: { run in run.bold ? theme.accent : theme.positive }, kind: .heading)
    case .listItem(let marker, let text, let depth):
      let indentation = String(repeating: "  ", count: min(depth, 4))
      var runs = [MarkdownRun(text: indentation + marker + " ")]
      runs.append(contentsOf: inlineRuns(text))
      wrapRuns(
        runs,
        colorFor: { run in
          if run.text == indentation + marker + " " { return theme.warning }
          return run.code ? theme.warning : run.bold ? theme.foreground : baseColor
        }, kind: .plain)
    case .quote(let text):
      var runs = [MarkdownRun(text: "| ")]
      runs.append(contentsOf: inlineRuns(text))
      wrapRuns(
        runs,
        colorFor: { run in
          run.text == "| " ? theme.positive : run.code ? theme.warning : run.bold ? theme.foreground : baseColor
        }, kind: .plain)
    case .code(_, let code):
      let codeLines = code.split(separator: "\n", omittingEmptySubsequences: false)
      if codeLines.isEmpty {
        lines.append(VisualLine(kind: .code, runs: [VisualRun(text: "", color: theme.foreground)]))
      }
      for rawLine in codeLines {
        var rest = String(rawLine)
        if rest.isEmpty {
          lines.append(VisualLine(kind: .code, runs: [VisualRun(text: "", color: theme.foreground)]))
        }
        while !rest.isEmpty {
          let take = min(columns, rest.count)
          let cut = rest.index(rest.startIndex, offsetBy: take)
          let remainder = String(rest[cut...])
          lines.append(
            VisualLine(
              kind: .code,
              runs: [VisualRun(text: String(rest[..<cut]), color: theme.foreground)],
              columnCount: take,
              trailingText: remainder.isEmpty ? "\n" : ""))
          rest = remainder
        }
      }
    case .rule:
      lines.append(
        VisualLine(
          kind: .plain,
          runs: [VisualRun(text: String(repeating: "─", count: min(columns, 40)), color: theme.positive)],
          columnCount: min(columns, 40)))
    }
    previousWasListItem = isListItem
  }
  while let last = lines.last, last.columnCount == 0, last.kind != .code { lines.removeLast() }
  return lines
}
