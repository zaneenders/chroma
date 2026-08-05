import Chroma
import Foundation

struct AsciiPanel: PrimitiveBlock {
  let theme: Theme
  let state: DemoState

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let printableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
      let last = min(first + 0x0f, 0x7e)
      return Array(String(format: "%02X  ", first).utf8) + (first...last).map(UInt8.init)
    }
    let lines = [Array("20x28 PRINTABLE  ASCII  20..7E".utf8)] + printableRows

    let metrics = FontMetrics()
    let availableWidth = rect.size.width - 2 * theme.panelPadding
    let availableHeight = rect.size.height - 2 * theme.panelPadding
    let longestLine = Float(lines.map(\.count).max() ?? 1)
    let widthScale = availableWidth / (longestLine * metrics.cellAdvance)
    let heightScale = availableHeight / (Float(lines.count) * metrics.lineAdvance)
    let scale = max(1, min(3, floor(min(widthScale, heightScale))))
    let origin = Point(x: rect.minX + theme.panelPadding, y: rect.minY + theme.panelPadding)

    if state.grid {
      let gridColor = Color(r: 0.5, g: 0.6, b: 0.8, a: 0.06)
      var x =
        rect.minX
        + (metrics.cellAdvance * scale - rect.minX.truncatingRemainder(dividingBy: metrics.cellAdvance * scale))
      while x < rect.maxX {
        drawList.fillRect(Rect(x: x.rounded(), y: rect.minY, width: 1, height: rect.size.height), color: gridColor)
        x += metrics.cellAdvance * scale
      }
      var y =
        rect.minY
        + (metrics.lineAdvance * scale - rect.minY.truncatingRemainder(dividingBy: metrics.lineAdvance * scale))
      while y < rect.maxY {
        drawList.fillRect(Rect(x: rect.minX, y: y.rounded(), width: rect.size.width, height: 1), color: gridColor)
        y += metrics.lineAdvance * scale
      }
    }

    if state.axis {
      let axisColor = Color(r: state.accent.r, g: state.accent.g, b: state.accent.b, a: 0.55)
      let midX = (rect.minX + rect.size.width / 2).rounded()
      let midY = (rect.minY + rect.size.height / 2).rounded()
      drawList.fillRect(Rect(x: rect.minX, y: midY, width: rect.size.width, height: 1), color: axisColor)
      drawList.fillRect(Rect(x: midX, y: rect.minY, width: 1, height: rect.size.height), color: axisColor)
    }

    for (row, bytes) in lines.enumerated() {
      drawList.text(
        String(decoding: bytes, as: UTF8.self),
        at: Point(
          x: origin.x,
          y: origin.y + Float(row) * metrics.lineAdvance * scale
        ),
        color: row == 0 ? theme.yellow : .white,
        scale: scale
      )
    }

    if state.wireframe {
      let boxColor = Color(r: 1, g: 1, b: 1, a: 0.22)
      for (row, bytes) in lines.enumerated() {
        for column in 0..<bytes.count {
          drawList.strokeRect(
            Rect(
              x: origin.x + Float(column) * metrics.cellAdvance * scale,
              y: origin.y + Float(row) * metrics.lineAdvance * scale,
              width: metrics.glyphWidth * scale,
              height: metrics.glyphHeight * scale
            ),
            width: 1,
            color: boxColor
          )
        }
      }
    }
  }
}
