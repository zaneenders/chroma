import Testing

@testable import Chroma

private struct FixedContent: PrimitiveBlock {
  var size: Size
  var focusRule: FocusRule { .standard }
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { size }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRect(rect, color: .white)
  }
}

private struct ClippedScrollContent: PrimitiveBlock {
  let content: any Block

  var focusRule: FocusRule { .container }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    context.withInteractionClip(Rect(x: 0, y: 0, width: 20, height: 20)) {
      BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    }
  }
}

private final class DrawCounter {
  var measured: [Int] = []
  var drawn: [Int] = []
}

private final class PhaseLog {
  var phases: [Int: InteractionPhase] = [:]
}

private struct CountedRow: PrimitiveBlock {
  let index: Int
  let height: Float
  let counter: DrawCounter

  var focusRule: FocusRule { .standard }

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

  var focusRule: FocusRule { .standard }

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

  @Test func keyboardNavigationRevealsFocusedScrollContent() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        ScrollView(id: scrollID, showsIndicator: false) {
          for _ in 0..<4 {
            Interactive(action: {}) { _ in
              RowContent(height: 10, color: .white)
            }
            .sizing(y: .fixed(10))
          }
        },
        into: &list,
        in: viewport,
        context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollOffset(for: scrollID) == 0)

    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollOffset(for: scrollID) == 10)
  }

  @Test func keyboardNavigationReachesSpacedVirtualizedRows() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: scrollID, data: 0..<5, rowHeight: 10, spacing: 10, showsIndicator: false, controller: controller)
        { index in
          Interactive(id: WidgetID("row-\(index)"), action: {}) { _ in
            RowContent(height: 10, color: .white)
          }
        },
        into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    for index in 1..<5 {
      frame(InputState(commands: [.navigation(.down)]))
      #expect(interaction.selectedLeafID == WidgetID("row-\(index)"))
    }
    frame()
    #expect(interaction.scrollOffset(for: scrollID) == 70)
  }

  @Test func keyboardFocusedRowsShowHoverPhase() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let controller = ScrollViewController()
    let listRect = Rect(x: 0, y: 0, width: 100, height: 40)
    let log = PhaseLog()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: scrollID, data: 0..<4, rowHeight: 10, showsIndicator: false, controller: controller) { index in
          Interactive(id: WidgetID("row-\(index)"), action: {}) { phase in
            log.phases[index] = phase
            return RowContent(height: 10, color: .white)
          }
        },
        into: &list, in: listRect, context: context)
      interaction.endFrame()
    }

    frame(InputState(pointerPosition: Point(x: 500, y: 500)))
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    #expect(interaction.selectedLeafID == WidgetID("row-1"))
    #expect(log.phases[0] == .idle)
    #expect(log.phases[1] == .hovered, "keyboard focus shows the hovered phase")

    frame(InputState(pointerPosition: Point(x: 5, y: 25)))
    #expect(interaction.selectedLeafID == WidgetID("row-1"), "hover does not move keyboard focus")
    #expect(log.phases[2] == .hovered)
    #expect(log.phases[3] == .idle)
    #expect(log.phases[2] == log.phases[1], "pointer hover and keyboard focus share one UI state")
  }

  @Test func keyboardNavigationReachesVariableHeightRowsInBothDirections() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let controller = ScrollViewController()
    let heights: [Float] = [8, 18, 6, 15, 9]
    let rows = heights.enumerated().map { index, height in
      LazyVStack.Row(
        id: index,
        content: Interactive(id: WidgetID("row-\(index)"), action: {}) { _ in
          RowContent(height: height, color: .white)
        })
    }

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: scrollID, spacing: 7, showsIndicator: false, controller: controller, rows: rows),
        into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    for index in 1..<rows.count {
      frame(InputState(commands: [.navigation(.down)]))
      #expect(interaction.selectedLeafID == WidgetID("row-\(index)"))
    }
    for index in stride(from: rows.count - 2, through: 0, by: -1) {
      frame(InputState(commands: [.navigation(.up)]))
      #expect(interaction.selectedLeafID == WidgetID("row-\(index)"))
    }
  }

  @Test func keyboardNavigationHandlesMultipleVirtualizedMovementsInOneFrame() {
    let context = RenderContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let view = LazyVStack(
      id: scrollID, data: 0..<10, rowHeight: 10, spacing: 5, showsIndicator: false, controller: controller
    ) { index in
      Interactive(id: WidgetID("row-\(index)"), action: {}) { _ in
        RowContent(height: 10, color: .white)
      }
    }

    func frame(_ input: InputState = InputState()) {
      _ = producer.render(content: view, viewport: viewport.size, input: input, context: context, onChange: {})
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down), .navigation(.down), .navigation(.down)]))
    #expect(context.interaction.tree?.node(at: context.interaction.selection ?? [])?.rect.minY == 10)
    frame()
    #expect(context.interaction.scrollOffset(for: scrollID) == 35)
  }

  @Test func keyboardNavigationRevealsNestedScrollContent() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let outerID = WidgetID("outer-scroll")
    let innerID = WidgetID("inner-scroll")

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        ScrollView(id: outerID, showsIndicator: false) {
          ScrollView(id: innerID, showsIndicator: false) {
            for index in 0..<4 {
              Interactive(id: WidgetID("row-\(index)"), action: {}) { _ in
                RowContent(height: 10, color: .white)
              }
              .sizing(y: .fixed(10))
            }
          }
          .sizing(y: .fixed(20))
        },
        into: &list, in: viewport, context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.selectedLeafID == WidgetID("row-2"))
    #expect(interaction.scrollOffset(for: innerID) == 10)
    #expect(interaction.scrollOffset(for: outerID) == 0)
  }

  @Test func keyboardNavigationRevealsVirtualizedRows() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: scrollID, data: 0..<10, rowHeight: 10, showsIndicator: false, controller: controller) { _ in
          Interactive(action: {}) { _ in
            RowContent(height: 10, color: .white)
          }
        },
        into: &list,
        in: viewport,
        context: context)
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollOffset(for: scrollID) == 10)
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

  @Test(
    arguments: [false, true],
    ["first", "normal", "reset"])
  func clippedRevealRespectsWheelHitTesting(lazy: Bool, frameState: String) {
    for pointer in [Point(x: 10, y: 10), Point(x: 10, y: 50), Point(x: 50, y: 10)] {
      for delta in [Point.zero, Point(x: 0, y: -12), Point(x: -12, y: 0)] {
        let context = RenderContext()
        let producer = FrameProducer()
        let controller = ScrollViewController()
        let scroll: any Block =
          lazy
          ? LazyVStack(id: scrollID, data: 0..<100, rowHeight: 10, controller: controller) { _ in
            Text("Row")
          }
          : ScrollView(id: scrollID, controller: controller) {
            FixedContent(size: Size(width: 1000, height: 1000))
          }
        func frame(_ input: InputState = InputState()) {
          _ = producer.render(
            content: ClippedScrollContent(content: scroll), viewport: Size(width: 100, height: 100),
            input: input, context: context, onChange: {})
        }
        if frameState != "first" { frame() }
        if frameState == "reset" { producer.reset() }
        controller.scrollToVisible(Rect(x: 500, y: 500, width: 10, height: 10))
        frame(InputState(pointerPosition: pointer, scrollDelta: delta))
        let receivesWheel = pointer == Point(x: 10, y: 10) && (delta.y != 0 || (!lazy && delta.x != 0))
        let expectedY: Float = receivesWheel ? -delta.y : 410
        let expectedX: Float = lazy ? 0 : receivesWheel ? -delta.x : 410
        #expect(context.interaction.scrollOffset(for: scrollID) == expectedY)
        #expect(context.interaction.horizontalScrollOffset(for: scrollID) == expectedX)
        #expect(controller.request == nil)
        frame()
        #expect(context.interaction.scrollOffset(for: scrollID) == expectedY)
        #expect(context.interaction.horizontalScrollOffset(for: scrollID) == expectedX)
      }
    }
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

  @Test func lazyStackCachePreservesDistinctKeyTypesAcrossReordering() {
    let context = RenderContext()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    let first = LazyVStack.Row(
      id: Int(1), content: CountedRow(index: 0, height: 10, counter: counter))
    let second = LazyVStack.Row(
      id: Int64(1), content: CountedRow(index: 1, height: 20, counter: counter))

    func frame(_ rows: [LazyVStack.Row]) {
      counter.measured = []
      counter.drawn = []
      context.interaction.beginFrame(input: InputState())
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(controller: controller, rows: rows),
        into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100), context: context)
      context.interaction.endFrame()
    }

    frame([first, second])
    #expect(counter.measured == [0, 1])
    let measurements = controller.lazyStackCache.measurements
    frame([second, first])
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [1, 0])
    #expect(controller.lazyStackCache.measurements[0] === measurements[1])
    #expect(controller.lazyStackCache.measurements[1] === measurements[0])
    #expect(controller.lazyStackCache.rowSizes.map(\.height) == [20, 10])

    var replacement = first
    replacement.content = CountedRow(index: 2, height: 30, counter: counter)
    frame([second, replacement])
    #expect(counter.measured == [2])
    #expect(controller.lazyStackCache.measurements[0] === measurements[1])
    #expect(controller.lazyStackCache.rowSizes.map(\.height) == [20, 30])
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
    interaction.focusFirstControlForTest()
    frame(InputState(pointerPosition: Point(x: 50, y: 50)))
    #expect(interaction.selection == [0, 0])
    frame(InputState(pointerPosition: Point(x: 50, y: 15)))
    #expect(interaction.selection == [0, 0])
    #expect(interaction.hoveredLeafID == WidgetID("clipped"))
  }
}
