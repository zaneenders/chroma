import Testing

@testable import Chroma

private struct FixedContent: PrimitiveBlock {
  var size: Size
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { size }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRect(rect, color: .white)
  }
}

private final class DrawCounter {
  var measured: [Int] = []
  var drawn: [Int] = []
}

private struct CountedRow: PrimitiveBlock {
  let index: Int
  let height: Float
  let counter: DrawCounter

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    counter.measured.append(index)
    return Size(width: proposal.width, height: height)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    counter.drawn.append(index)
  }
}

private struct RowContent: PrimitiveBlock {
  let height: Float
  let color: Color

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: proposal.width, height: height)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRect(rect, color: color)
  }
}

@Suite(.serialized)
@MainActor
struct ScrollViewTests {
  private let viewport = Rect(x: 0, y: 0, width: 100, height: 20)
  private let scrollID = WidgetID("test-scroll")

  private func drawFrame(
    _ interaction: Interaction,
    input: InputState = InputState(),
    controller: ScrollViewController? = nil,
    sticksToBottom: Bool = false
  ) -> DrawList {
    let context = RenderContext(interaction: interaction)
    interaction.beginFrame(input: input)
    var list = DrawList()
    let view = ScrollView(
      id: scrollID, showsIndicator: true, sticksToBottom: sticksToBottom,
      controller: controller
    ) {
      FixedContent(size: Size(width: 100, height: 100))
    }
    BlockEngine.draw(view, into: &list, in: viewport, context: context)
    interaction.endFrame()
    return list
  }

  @Test func wheelRetainsOffsetAndProducesBalancedClip() {
    let interaction = Interaction()
    _ = drawFrame(interaction)
    let list = drawFrame(
      interaction,
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -15))
    )

    #expect(interaction.scrollOffset(for: scrollID) == 15)
    #expect(list.commands.first == .pushClip(viewport))
    #expect(list.commands.last == .popClip)
  }

  @Test func horizontalWheelRetainsOffsetAndMovesWideContent() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) -> DrawList {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: input)
      var list = DrawList()
      let view = ScrollView(id: scrollID, showsIndicator: true) {
        FixedContent(size: Size(width: 200, height: 20))
      }
      BlockEngine.draw(view, into: &list, in: viewport, context: context)
      interaction.endFrame()
      return list
    }

    _ = frame()
    let list = frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: -15, y: 0)))

    #expect(interaction.horizontalScrollOffset(for: scrollID) == 15)
    #expect(interaction.horizontalScrollLimit(for: scrollID) == 100)
    #expect(
      list.commands.contains(
        .fillRect(
          rect: Rect(x: -15, y: 0, width: 200, height: 20), color: .white)))
  }

  @Test func simultaneousScrollViewsKeepIndependentOffsets() {
    let interaction = Interaction()
    let firstID = WidgetID("first-scroll")
    let secondID = WidgetID("second-scroll")
    let firstViewport = Rect(x: 0, y: 0, width: 100, height: 20)
    let secondViewport = Rect(x: 0, y: 30, width: 100, height: 20)

    func frame(_ input: InputState = InputState()) {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        ScrollView(id: firstID) { FixedContent(size: Size(width: 100, height: 100)) },
        into: &list, in: firstViewport, context: context)
      BlockEngine.draw(
        ScrollView(id: secondID) { FixedContent(size: Size(width: 100, height: 100)) },
        into: &list, in: secondViewport, context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -15)))
    #expect(interaction.scrollOffset(for: firstID) == 15)
    #expect(interaction.scrollOffset(for: secondID) == 0)

    frame(InputState(pointerPosition: Point(x: 10, y: 40), scrollDelta: Point(x: 0, y: -25)))
    #expect(interaction.scrollOffset(for: firstID) == 15)
    #expect(interaction.scrollOffset(for: secondID) == 25)
  }

  @Test func controllerScrollsToBottom() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)
    controller.scrollToBottom()
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 80)
  }

  @Test func controllerScrollsOnlyEnoughToRevealRectHorizontally() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame() {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let view = ScrollView(id: scrollID, controller: controller) {
        FixedContent(size: Size(width: 200, height: 20))
      }
      BlockEngine.draw(view, into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    controller.scrollToVisible(Rect(x: 125, y: 0, width: 10, height: 10))
    frame()
    #expect(interaction.horizontalScrollOffset(for: scrollID) == 35)
  }

  @Test func wheelInputWinsOverPendingRevealRequest() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: input)
      var list = DrawList()
      let view = ScrollView(id: scrollID, controller: controller) {
        FixedContent(size: Size(width: 100, height: 100))
      }
      BlockEngine.draw(view, into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    controller.scrollToVisible(Rect(x: 0, y: 25, width: 100, height: 10))
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: 0, y: -12)))
    #expect(interaction.scrollOffset(for: scrollID) == 12)
  }

  @Test(arguments: [(false, false), (false, true), (true, false)], ["first", "normal", "reset"])
  func frameProducerWheelCancelsPendingRevealRequest(configuration: (Bool, Bool), frameState: String) {
    let (lazy, horizontal) = configuration
    let context = RenderContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let view: any Block =
      lazy
      ? LazyVStack(id: scrollID, data: 0..<100, rowHeight: 10, controller: controller) { _ in
        Text("Row")
      }
      : ScrollView(id: scrollID, controller: controller) {
        FixedContent(size: Size(width: 1000, height: 1000))
      }
    func frame(_ input: InputState = InputState()) {
      _ = producer.render(
        content: view, viewport: viewport.size, input: input, context: context, onChange: {})
    }

    if frameState != "first" { frame() }
    if frameState == "reset" { producer.reset() }
    controller.scrollToVisible(Rect(x: 500, y: 500, width: 10, height: 10))
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: horizontal ? Point(x: -12, y: 0) : Point(x: 0, y: -12)))

    #expect(context.interaction.scrollOffset(for: scrollID) == (horizontal ? 0 : 12))
    #expect(context.interaction.horizontalScrollOffset(for: scrollID) == (horizontal ? 12 : 0))
    #expect(controller.request == nil)
    frame()
    #expect(context.interaction.scrollOffset(for: scrollID) == (horizontal ? 0 : 12))
    #expect(context.interaction.horizontalScrollOffset(for: scrollID) == (horizontal ? 12 : 0))
  }

  @Test(arguments: [false, true], ["first", "normal", "reset"])
  func frameProducerAppliesExplicitScrollRequestAfterWheel(lazy: Bool, frameState: String) {
    let context = RenderContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let view: any Block =
      lazy
      ? LazyVStack(id: scrollID, data: 0..<100, rowHeight: 10, controller: controller) { _ in
        Text("Row")
      }
      : ScrollView(id: scrollID, controller: controller) {
        FixedContent(size: Size(width: 100, height: 1000))
      }
    func frame(_ input: InputState = InputState()) {
      _ = producer.render(
        content: view, viewport: viewport.size, input: input, context: context, onChange: {})
    }

    if frameState != "first" { frame() }
    if frameState == "reset" { producer.reset() }
    controller.scroll(to: 50)
    frame(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -12)))
    #expect(context.interaction.scrollOffset(for: scrollID) == 50)
    #expect(controller.request == nil)
  }

  @Test(arguments: [Point.zero, Point(x: 0, y: -12), Point(x: -12, y: 0)])
  func lazyRevealSurvivesUnrelatedWheelInput(delta: Point) {
    let context = RenderContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let view = LazyVStack(id: scrollID, data: 0..<100, rowHeight: 10, controller: controller) { _ in
      Text("Row")
    }
    controller.scrollToVisible(Rect(x: 0, y: 500, width: 10, height: 10))
    _ = producer.render(
      content: view, viewport: viewport.size,
      input: InputState(
        pointerPosition: delta.y != 0 ? Point(x: 200, y: 200) : Point(x: 10, y: 10),
        scrollDelta: delta),
      context: context, onChange: {})
    #expect(context.interaction.scrollOffset(for: scrollID) == 490)
    #expect(controller.request == nil)
  }

  @Test func oversizedRevealTargetDoesNotFightHorizontalScrolling() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: input)
      var list = DrawList()
      let view = ScrollView(id: scrollID, controller: controller) {
        FixedContent(size: Size(width: 200, height: 20))
      }
      BlockEngine.draw(view, into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: -40, y: 0)))
    #expect(interaction.horizontalScrollOffset(for: scrollID) == 40)

    controller.scrollToVisible(Rect(x: -40, y: 0, width: 200, height: 10))
    frame()
    #expect(interaction.horizontalScrollOffset(for: scrollID) == 40)
  }

  @Test func controllerScrollsOnlyEnoughToRevealRect() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)

    controller.scrollToVisible(Rect(x: 0, y: 25, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 15)

    controller.scrollToVisible(Rect(x: 0, y: 5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 15)

    controller.scrollToVisible(Rect(x: 0, y: -5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 10)
  }

  @Test func loopRowsStackAndCreateScrollableContent() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    let colors = [
      Color(r: 1, g: 0, b: 0, a: 1),
      Color(r: 0, g: 1, b: 0, a: 1),
      Color(r: 0, g: 0, b: 1, a: 1),
    ]
    let view = ScrollView(id: scrollID, showsIndicator: true) {
      for color in colors {
        RowContent(height: 10, color: color)
      }
    }
    BlockEngine.draw(view, into: &list, in: viewport, context: context)
    interaction.endFrame()

    let rowRects = list.commands.compactMap { command -> Rect? in
      guard case .fillRect(let rect, let color) = command, colors.contains(color) else { return nil }
      return rect
    }
    #expect(rowRects.map(\.minY) == [0, 10, 20])
    #expect(interaction.scrollLimit(for: scrollID) == 10)
  }

  @Test func lazyStackMeasuresRowsOnceAndOnlyDrawsVisibleRows() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    let rows = (0..<10_000).map { index in
      LazyVStack.Row(
        id: WidgetID("row-\(index)"),
        content: CountedRow(index: index, height: 10, counter: counter))
    }

    func frame() {
      let context = RenderContext(interaction: interaction)
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let view = LazyVStack(
        id: scrollID, controller: controller, rows: rows)
      BlockEngine.draw(view, into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    #expect(counter.measured == Array(0..<10_000))
    #expect(counter.drawn == [0, 1, 2])

    counter.measured = []
    counter.drawn = []
    controller.scroll(to: 50)
    frame()
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [4, 5, 6, 7])

    counter.drawn = []
    controller.scrollToBottom()
    frame()
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [9_997, 9_998, 9_999])

    counter.drawn = []
    controller.scrollToTop()
    frame()
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [0, 1, 2])
  }

  @Test func dataDrivenLazyStackBuildsOnlyVisibleRows() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    var built: [Int] = []
    func row(_ index: Int) -> CountedRow {
      built.append(index)
      return CountedRow(index: index, height: 10, counter: counter)
    }
    func frame(_ data: ArraySlice<Int>, width: Float = 100, spacing: Float = 0) {
      built = []
      counter.drawn = []
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let stack = LazyVStack(
        id: scrollID, data: data, rowHeight: 10, spacing: spacing,
        controller: controller
      ) { index in row(index) }
      #expect(built.isEmpty)
      BlockEngine.draw(
        stack, into: &list, in: Rect(x: 0, y: 0, width: width, height: 20),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
      #expect(counter.measured.isEmpty)
      #expect(built == counter.drawn)
      #expect(built.count <= 4)
    }

    let data = Array(0..<10_001).dropFirst()
    frame(data)
    #expect(built == [1, 2, 3])
    controller.scrollToBottom()
    frame(data)
    #expect(built == [9_998, 9_999, 10_000])
    controller.scrollToTop()
    frame(data, width: 200)
    #expect(built == [1, 2, 3])

    frame(Array(20_001..<30_001)[...])
    #expect(built == [20_001, 20_002, 20_003])
    controller.scroll(to: 12)
    frame(data, spacing: 5)
    #expect(built == [2, 3])
    controller.scrollToBottom()
    frame([42][...])
    #expect(built == [42])
    #expect(interaction.scrollLimit(for: scrollID) == 0)
    frame([][...])
    #expect(built.isEmpty)
  }

  @Test func lazyStackCacheTracksReorderingReplacementAndWidth() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let counter = DrawCounter()

    let retainedRows = (0..<5).map { index in
      LazyVStack.Row(
        id: WidgetID("row-\(index)"),
        content: CountedRow(index: index, height: 10, counter: counter))
    }

    func frame(_ indices: [Int], width: Float = 100) {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let rows = indices.map { retainedRows[$0] }
      BlockEngine.draw(
        LazyVStack(id: scrollID, controller: controller, rows: rows),
        into: &list, in: Rect(x: 0, y: 0, width: width, height: 100),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
    }

    frame([0, 1, 2])
    counter.measured = []
    counter.drawn = []
    frame([2, 1, 0])
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [2, 1, 0])

    frame([2, 3, 0])
    #expect(counter.measured == [3])
    counter.measured = []
    frame([2, 3, 0], width: 200)
    #expect(counter.measured == [2, 3, 0])

    counter.measured = []
    frame([])
    frame([4])
    #expect(counter.measured == [4])
  }

  @Test func scrollInputRespectsClipOnBothAxes() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      interaction.pushClip(Rect(x: 0, y: 0, width: 50, height: 50))
      interaction.registerScrollInput(
        id: scrollID, rect: Rect(x: 0, y: 0, width: 100, height: 100), horizontal: true)
      interaction.setScrollLimit(100, for: scrollID)
      interaction.setHorizontalScrollLimit(100, for: scrollID)
      interaction.popClip()
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 75, y: 25), scrollDelta: Point(x: -10, y: -15)))
    #expect(interaction.scrollOffset(for: scrollID) == 0)
    #expect(interaction.horizontalScrollOffset(for: scrollID) == 0)
    frame(InputState(pointerPosition: Point(x: 25, y: 25), scrollDelta: Point(x: -10, y: -15)))
    #expect(interaction.scrollOffset(for: scrollID) == 15)
    #expect(interaction.horizontalScrollOffset(for: scrollID) == 10)
  }

  @Test func clippedLeafCannotBeHitOutsideViewport() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      interaction.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 100))
      _ = interaction.interactiveBehavior(
        id: WidgetID("visible"), rect: Rect(x: 0, y: 0, width: 100, height: 10))
      interaction.pushClip(Rect(x: 0, y: 10, width: 100, height: 10))
      _ = interaction.interactiveBehavior(
        id: WidgetID("clipped"), rect: Rect(x: 0, y: 10, width: 100, height: 90))
      interaction.popClip()
      interaction.endGroup()
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 50, y: 50)))
    #expect(interaction.selection == [0, 0])
    frame(InputState(pointerPosition: Point(x: 50, y: 15)))
    #expect(interaction.selection == [0, 1])
  }
}
