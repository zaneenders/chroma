import Chroma
import TerminalBackend
import Testing

struct TerminalRasterizerTests {
  @Test func fillsDrawsTextAndClips() {
    var list = DrawList()
    list.fillRect(Rect(x: 0, y: 0, width: 6, height: 2), color: .yellow)
    list.pushClip(Rect(x: 1, y: 0, width: 3, height: 1))
    list.text("hello", at: .zero, color: .black)
    list.popClip()

    let frame = TerminalRasterizer().rasterize(list.commands, columns: 6, rows: 2)

    #expect(frame.text(row: 0) == " ell  ")
    #expect(frame[column: 0, row: 0].background == TerminalRGB(r: 255, g: 199, b: 64))
  }

  @Test func strokesWithBoxDrawingCharacters() {
    var list = DrawList()
    list.strokeRect(Rect(x: 1, y: 1, width: 4, height: 3), width: 1, color: .white)

    let frame = TerminalRasterizer().rasterize(list.commands, columns: 6, rows: 5)

    #expect(frame.text(row: 1) == " ┌──┐ ")
    #expect(frame.text(row: 2) == " │  │ ")
    #expect(frame.text(row: 3) == " └──┘ ")
  }
}

@MainActor
struct TerminalRendererTests {
  @Test func rendersChromaContentInCellCoordinates() {
    let renderer = TerminalRenderer()
    renderer.content = Text("hello")

    let frame = renderer.render(columns: 8, rows: 2)

    #expect(frame.text(row: 0) == "hello   ")
  }
}
