import Testing

@testable import Chroma

@MainActor
struct LayoutTests {
  private let viewport = Rect(x: 0, y: 0, width: 400, height: 300)

  private func textPositions(in list: DrawList) -> [(String, Float)] {
    list.paintSnapshot.compactMap { command in
      guard case .text(let position, let text, _, _) = command else { return nil }
      return (text, position.y)
    }
  }

  private func chromeLine(
    _ title: String, height: Float, color: Color, into buffer: inout LayoutBuffer, context: LayoutContext
  ) -> LayoutNode {
    buffer.background(
      context: context,
      content: { buffer, context in
        let text = buffer.text(Text(title), context: context)
        return buffer.sizing(text, x: .grow, y: .fixed(height), context: context)
      }, background: { $0.color(color, context: $1) })
  }

  private func chrome(showQueue: Bool, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    var children: [LayoutNode] = []
    if showQueue {
      children.append(
        chromeLine(
          "QUEUED (1)", height: 24, color: Color(r: 0.2, g: 0.2, b: 0.3, a: 1), into: &buffer,
          context: context.childScope(0)))
    }
    children.append(
      chromeLine(
        "COMPOSER", height: 36, color: Color(r: 0.15, g: 0.15, b: 0.25, a: 1), into: &buffer,
        context: context.childScope(1)))
    children.append(
      chromeLine(
        "STATUS", height: 24, color: Color(r: 0.12, g: 0.12, b: 0.18, a: 1), into: &buffer,
        context: context.childScope(2)))
    let column = buffer.stack(children, axis: .vertical, context: context)
    return buffer.sizing(column, x: .grow, context: context)
  }

  private func readyScene(includeHeader: Bool, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let contentContext = context.childScope(1)
    let transcriptContext = contentContext.childScope(0)
    let color = buffer.color(Color(r: 0.1, g: 0.1, b: 0.2, a: 1), context: transcriptContext)
    let transcript = buffer.sizing(color, x: .grow, y: .grow, context: transcriptContext)
    let chrome = chrome(showQueue: true, into: &buffer, context: contentContext.childScope(1))
    let column = buffer.stack([transcript, chrome], axis: .vertical, context: contentContext)
    let content = buffer.sizing(column, x: .grow, y: .grow, context: contentContext)
    guard includeHeader else { return content }
    let headerContext = context.childScope(0)
    let header = buffer.text(Text("HEADER"), context: headerContext)
    let headerSized = buffer.sizing(header, x: .grow, y: .fixed(40), context: headerContext)
    return buffer.stack([headerSized, content], axis: .vertical, context: context)
  }

  @Test func readyLayoutPinsBottomChromeBelowTranscript() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = readyScene(includeHeader: true, into: &resolvedBuffer, context: context)
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &list, in: viewport)
    }
    interaction.endFrame()

    let positions = textPositions(in: list)
    let headerY = positions.first { $0.0 == "HEADER" }?.1
    let queuedY = positions.first { $0.0 == "QUEUED (1)" }?.1
    let composerY = positions.first { $0.0 == "COMPOSER" }?.1
    let statusY = positions.first { $0.0 == "STATUS" }?.1

    #expect(headerY == 0)
    #expect(queuedY != nil)
    #expect(composerY != nil)
    #expect(statusY != nil)
    #expect(queuedY! > headerY! + 40)
    #expect(composerY! > queuedY!)
    #expect(statusY! > composerY!)
    #expect(queuedY! > viewport.size.height * 0.65)
    #expect(statusY! < viewport.size.height)
  }

  @Test func factoredBottomChromeStillStacksChildren() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = readyScene(includeHeader: false, into: &resolvedBuffer, context: context)
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &list, in: viewport)
    }
    interaction.endFrame()

    let positions = textPositions(in: list)
    let queuedY = positions.first { $0.0 == "QUEUED (1)" }?.1
    let composerY = positions.first { $0.0 == "COMPOSER" }?.1
    let statusY = positions.first { $0.0 == "STATUS" }?.1

    #expect(queuedY != nil)
    #expect(composerY != nil)
    #expect(statusY != nil)
    #expect(composerY! > queuedY!)
    #expect(statusY! > composerY!)
    #expect(queuedY! > viewport.size.height * 0.65)
  }

  @Test func sizingResolvesEachAxisIndependently() {
    let proposal = Size(width: 400, height: 300)
    let context = LayoutContext()
    let fitted: LayoutBuilder = { buffer, context in
      let text = buffer.text(Text("fit"), context: context)
      return buffer.sizing(text, context: context)
    }
    let fixed: LayoutBuilder = { buffer, context in
      let text = buffer.text(Text("fixed"), context: context)
      return buffer.sizing(text, x: .fixed(120), y: .fixed(48), context: context)
    }
    let horizontalGrow: LayoutBuilder = { buffer, context in
      let text = buffer.text(Text("grow"), context: context)
      return buffer.sizing(text, x: .grow, context: context)
    }
    let verticalGrow: LayoutBuilder = { buffer, context in
      let text = buffer.text(Text("grow"), context: context)
      return buffer.sizing(text, y: .grow, context: context)
    }

    let fittedTextSize = measureLayout({ $0.text(Text("fit"), context: $1) }, proposal: proposal, context: context)
    #expect(measureLayout(fitted, proposal: proposal, context: context) == fittedTextSize)
    #expect(measureLayout(fixed, proposal: proposal, context: context) == Size(width: 120, height: 48))
    #expect(measureLayout(horizontalGrow, proposal: proposal, context: context).width == 400)
    #expect(measureLayout(verticalGrow, proposal: proposal, context: context).height == 300)

    #expect(!layoutExpandsHorizontally(fitted))
    #expect(!layoutExpandsVertically(fitted))
    #expect(!layoutExpandsHorizontally(fixed))
    #expect(!layoutExpandsVertically(fixed))
    #expect(layoutExpandsHorizontally(horizontalGrow))
    #expect(!layoutExpandsVertically(horizontalGrow))
    #expect(!layoutExpandsHorizontally(verticalGrow))
    #expect(layoutExpandsVertically(verticalGrow))
  }

  @Test func reverseLayoutFlipsStackChildOrder() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    beginTestFrame(interaction, input: InputState())

    var horizontalList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let first = resolvedBuffer.text(Text("first"), context: context.childScope(0))
      let second = resolvedBuffer.text(Text("second"), context: context.childScope(1))
      let resolved = resolvedBuffer.stack([first, second], axis: .horizontal, reversed: true, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &horizontalList, in: rect)
    }
    interaction.endFrame()
    beginTestFrame(interaction, input: InputState())

    var verticalList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let first = resolvedBuffer.text(Text("first"), context: context.childScope(0))
      let second = resolvedBuffer.text(Text("second"), context: context.childScope(1))
      let resolved = resolvedBuffer.stack([first, second], axis: .vertical, reversed: true, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &verticalList, in: rect)
    }
    interaction.endFrame()

    let horizontalText = horizontalList.paintSnapshot.compactMap { command -> (String, Point)? in
      guard case .text(let position, let text, _, _) = command else { return nil }
      return (text, position)
    }
    let verticalText = verticalList.paintSnapshot.compactMap { command -> (String, Point)? in
      guard case .text(let position, let text, _, _) = command else { return nil }
      return (text, position)
    }

    #expect(horizontalText.map(\.0) == ["first", "second"])
    #expect(horizontalText[0].1.x > horizontalText[1].1.x)
    #expect(verticalText.map(\.0) == ["first", "second"])
    #expect(verticalText[0].1.y > verticalText[1].1.y)
  }

  @Test func spacerOnlyExpandsAlongItsStackAxis() {
    let horizontal: LayoutBuilder = { buffer, context in
      let left = buffer.text(Text("left"), context: context.childScope(0))
      let spacer = buffer.spacer(context: context.childScope(1))
      let right = buffer.text(Text("right"), context: context.childScope(2))
      return buffer.stack([left, spacer, right], axis: .horizontal, context: context)
    }
    let vertical: LayoutBuilder = { buffer, context in
      let top = buffer.text(Text("top"), context: context.childScope(0))
      let spacer = buffer.spacer(context: context.childScope(1))
      let bottom = buffer.text(Text("bottom"), context: context.childScope(2))
      return buffer.stack([top, spacer, bottom], axis: .vertical, context: context)
    }
    let proposal = Size(width: 400, height: 300)
    let context = LayoutContext()

    #expect(layoutExpandsHorizontally(horizontal))
    #expect(!layoutExpandsVertically(horizontal))
    #expect(measureLayout(horizontal, proposal: proposal, context: context).height < proposal.height)

    #expect(!layoutExpandsHorizontally(vertical))
    #expect(layoutExpandsVertically(vertical))
    #expect(measureLayout(vertical, proposal: proposal, context: context).width < proposal.width)
  }
}
