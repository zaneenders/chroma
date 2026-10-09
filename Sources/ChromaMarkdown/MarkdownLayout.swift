import Chroma

enum MarkdownBlock: Equatable, Sendable {
  case paragraph(String)
  case code(language: String?, code: String)
  case heading(level: Int, text: String)
  case listItem(marker: String, text: String, depth: Int)
  case quote(String)
  case rule
}

struct MarkdownRun: Equatable, Sendable {
  var text: String
  var code: Bool = false
  var bold: Bool = false
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

/// Only the colors baked into visual runs participate in wrap-plan invalidation.
struct MarkdownColors: Equatable {
  let foreground: Color
  let accent: Color
  let positive: Color
  let warning: Color

  init(_ theme: ChromaTheme) {
    foreground = theme.foreground
    accent = theme.accent
    positive = theme.positive
    warning = theme.warning
  }
}

func layoutMarkdown(
  _ parsed: ParsedMarkdownBlock, columns: Int, colors: MarkdownColors
) -> MarkdownLinePlan {
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

  switch parsed.block {
  case .paragraph:
    wrapRuns(
      parsed.runs,
      colorFor: { run in
        run.code ? colors.warning : colors.foreground
      }, kind: .plain)
  case .heading(let level, _):
    let prefix = String(repeating: "#", count: level) + " "
    wrapRuns(
      [MarkdownRun(text: prefix)]
        + parsed.runs.map {
          var run = $0
          run.bold = true
          return run
        },
      colorFor: { run in run.bold ? colors.accent : colors.positive }, kind: .heading)
  case .listItem(let marker, _, let depth):
    let indentation = String(repeating: "  ", count: min(depth, 4))
    var runs = [MarkdownRun(text: indentation + marker + " ")]
    runs.append(contentsOf: parsed.runs)
    wrapRuns(
      runs,
      colorFor: { run in
        if run.text == indentation + marker + " " { return colors.warning }
        return run.code ? colors.warning : colors.foreground
      }, kind: .plain)
  case .quote:
    var runs = [MarkdownRun(text: "| ")]
    runs.append(contentsOf: parsed.runs)
    wrapRuns(
      runs,
      colorFor: { run in
        run.text == "| " ? colors.positive : run.code ? colors.warning : colors.foreground
      }, kind: .plain)
  case .code(_, let code):
    let codeLines = code.split(separator: "\n", omittingEmptySubsequences: false)
    if codeLines.isEmpty {
      lines.append(VisualLine(kind: .code, runs: [VisualRun(text: "", color: colors.foreground)]))
    }
    for rawLine in codeLines {
      var rest = String(rawLine)
      if rest.isEmpty {
        lines.append(VisualLine(kind: .code, runs: [VisualRun(text: "", color: colors.foreground)]))
      }
      while !rest.isEmpty {
        let take = min(columns, rest.count)
        let cut = rest.index(rest.startIndex, offsetBy: take)
        let remainder = String(rest[cut...])
        lines.append(
          VisualLine(
            kind: .code,
            runs: [VisualRun(text: String(rest[..<cut]), color: colors.foreground)],
            columnCount: take,
            trailingText: remainder.isEmpty ? "\n" : ""))
        rest = remainder
      }
    }
  case .rule:
    lines.append(
      VisualLine(
        kind: .plain,
        runs: [VisualRun(text: String(repeating: "─", count: min(columns, 40)), color: colors.positive)],
        columnCount: min(columns, 40)))
  }
  while let last = lines.last, last.columnCount == 0, last.kind != .code { lines.removeLast() }
  if parsed.hasLeadingGap { lines.insert(VisualLine(), at: 0) }
  return MarkdownLinePlan(lines: lines, hasLeadingGap: parsed.hasLeadingGap)
}
