import Chroma

public enum TranscriptReplay {
  public static let names = ["transcript", "streaming", "scrolling", "selection", "composer"]
  public static let frameCount = 60

  public static func make(name: String, historyLines: Int) -> [DrawList] {
    precondition(names.contains(name) && historyLines > 0)
    return (0..<frameCount).map { frame in
      var list = DrawList()
      let background = Color(r: 0.06, g: 0.07, b: 0.1, a: 1)
      let panel = Color(r: 0.12, g: 0.13, b: 0.18, a: 1)
      let accent = Color(r: 0.3, g: 0.6, b: 1, a: 1)
      list.fillRect(Rect(x: 0, y: 0, width: 1100, height: 720), color: background)
      list.pushClip(Rect(x: 0, y: 0, width: 230, height: 720))
      for row in 0..<18 {
        let y = Float(row * 36 + 12)
        if row == 3 {
          list.fillRoundedRect(Rect(x: 8, y: y, width: 212, height: 32), radius: 4, color: panel)
        }
        list.text("Session \(row): review renderer", at: Point(x: 16, y: y + 4), color: .white, scale: 0.5)
      }
      list.popClip()
      let composerLines = name == "composer" ? 1 + frame / 10 : 2
      let composerHeight = Float(composerLines * 20 + 32)
      let bottom = 696 - composerHeight
      let clip = Rect(x: 240, y: 12, width: 848, height: bottom - 24)
      list.pushClip(clip)
      let visible = max(1, Int(clip.size.height / 20))
      let first = name == "scrolling" ? (frame * 3) % max(1, historyLines - visible) : max(0, historyLines - visible)
      for row in 0..<min(historyLines, visible + 1) {
        let line = first + row
        let y = 12 + Float(row * 20) - (name == "scrolling" ? Float(frame % 5) * 2 : 0)
        if line % 8 == 0 {
          list.fillRect(Rect(x: 248, y: y, width: 828, height: 20), color: panel)
          list.text("tool: shell | Sources/Renderer.swift:\(line)", at: Point(x: 256, y: y), color: accent, scale: 0.5)
        } else {
          let selected = name == "selection" && row >= 3 && row <= 3 + frame / 4
          if selected {
            list.fillRect(Rect(x: 256, y: y, width: 720, height: 20), color: accent)
          }
          let runs = ["\(line) ", "let ", "result", " = ", "render", "(viewport)", " // cached frame"]
          var x: Float = 256
          for (index, run) in runs.enumerated() {
            list.text(
              run, at: Point(x: x, y: y), color: selected ? background : (index % 2 == 0 ? .white : accent), scale: 0.5)
            x += Float(run.count) * 6
          }
        }
      }
      if name == "streaming" {
        let text = String(
          "Streaming response: reuse stable layout, then encode only changed content.".prefix(frame + 1))
        list.fillRect(Rect(x: 248, y: bottom - 28, width: 828, height: 24), color: background)
        list.text(text, at: Point(x: 256, y: bottom - 26), color: .white, scale: 0.5)
      }
      list.popClip()
      let composer = Rect(x: 248, y: bottom, width: 828, height: composerHeight)
      list.fillRoundedRect(composer, radius: 6, color: panel)
      list.strokeRoundedRect(composer, radius: 6, width: 1, color: accent)
      list.pushClip(composer)
      for line in 0..<composerLines {
        list.text(
          "Inspect the rendering path and add tests \(line)", at: Point(x: 260, y: bottom + 12 + Float(line * 20)),
          color: .white, scale: 0.5)
      }
      list.fillRect(
        Rect(x: 524 + Float(frame % 10) * 6, y: bottom + 12 + Float((composerLines - 1) * 20), width: 1, height: 16),
        color: .white)
      list.popClip()
      list.text("READY | project/chroma | model | context 42%", at: Point(x: 248, y: 700), color: accent, scale: 0.5)
      return list
    }
  }
}
