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

  @Test func adjacentSubcellFillsDoNotBleedAcrossTheirSharedEdge() {
    var list = DrawList()
    list.fillRect(Rect(x: 0, y: 0, width: 14, height: 10), color: .yellow)
    list.fillRect(Rect(x: 0, y: 10, width: 14, height: 18), color: .black)

    let frame = TerminalRasterizer().rasterize(
      list.commands,
      columns: 2,
      rows: 2,
      pointsPerCell: Size(width: 14, height: 28))

    #expect(frame[column: 0, row: 0].background == .black)
  }

  @Test func compactRoundedControlsUseTheirFillInsteadOfBoxGlyphs() {
    var list = DrawList()
    list.fillRoundedRect(
      Rect(x: 1, y: 0, width: 12, height: 2), radius: 1, color: .yellow)
    list.strokeRoundedRect(
      Rect(x: 1, y: 0, width: 12, height: 2), radius: 1, width: 1,
      color: .white)

    let frame = TerminalRasterizer().rasterize(list.commands, columns: 14, rows: 3)

    #expect(frame.text(row: 0) == String(repeating: " ", count: 14))
    #expect(frame[column: 1, row: 0].background == TerminalRGB(r: 255, g: 199, b: 64))
  }

  @Test func bordersDoNotEraseTextInTheSameCellRow() {
    var list = DrawList()
    list.text("Navigation", at: Point(x: 2, y: 1), color: .white)
    list.strokeRoundedRect(
      Rect(x: 1, y: 0, width: 12, height: 2), radius: 1, width: 1,
      color: .white)

    let frame = TerminalRasterizer().rasterize(list.commands, columns: 14, rows: 3)

    #expect(frame.text(row: 1).contains("Navigation"))
  }

  @Test func projectsPointCoordinatesOntoTerminalCells() {
    var list = DrawList()
    list.fillRect(Rect(x: 22, y: 28, width: 22, height: 28), color: .yellow)
    list.text("hi", at: Point(x: 11, y: 56), color: .white)

    let frame = TerminalRasterizer().rasterize(
      list.commands,
      columns: 6,
      rows: 4,
      pointsPerCell: Size(width: 11, height: 28))

    #expect(frame[column: 2, row: 1].background == TerminalRGB(r: 255, g: 199, b: 64))
    #expect(frame[column: 3, row: 1].background == TerminalRGB(r: 255, g: 199, b: 64))
    #expect(frame.text(row: 2) == " hi   ")
  }
}

@MainActor
struct TerminalRendererTests {
  @Test func rendersChromaContentInCellCoordinates() {
    let renderer = TerminalRenderer(pointsPerCell: Size(width: 1, height: 1))
    renderer.content = Text("hello")

    let frame = renderer.render(columns: 8, rows: 2)

    #expect(frame.text(row: 0) == "hello   ")
  }

  @Test func nativePointLayoutDoesNotCollapseScaledDemoText() {
    let renderer = TerminalRenderer(pointsPerCell: Size(width: 11, height: 28))
    renderer.content = HStack(spacing: 10) {
      Text("CHROMA").fontScale(0.9)
      Text("Demo").fontScale(0.65)
    }

    let frame = renderer.render(columns: 30, rows: 3)

    #expect(frame.text(row: 0).contains("CHROMA"))
    #expect(frame.text(row: 0).contains("Demo"))
  }
}
