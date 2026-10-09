import Testing

@testable import Chroma

private struct FixedContent {

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      expandsHorizontally: false, expandsVertically: false,
      measure: { sizeThatFits($0, context: context) },
      register: { register(in: $0, context: context) },
      paint: { paint(into: &$0, in: $1, context: context) })
  }

  @MainActor func register(in rect: Rect, context: LayoutContext) {}

  var size: Size
  var focusRule: FocusRule { .standard }
  @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size { size }
  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: LayoutContext) {
    drawList.fillRect(rect, color: .white)
  }
}

private struct ClippedScrollContent {
  let content: ScrollView
  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let child = buffer.scrollView(content, context: context)
    let padded = buffer.padding(child, EdgeInsets(bottom: -80, trailing: -80), context: context)
    let sized = buffer.sizing(padded, x: .fixed(20), y: .fixed(20), context: context)
    let clipped = buffer.clip(sized, context: context)
    return buffer.overlay([clipped], context: context)
  }
}

private final class DrawCounter {
  var measured: [Int] = []
  var drawn: [Int] = []
}

private final class PhaseLog {
  var phases: [Int: InteractionPhase] = [:]
}

private struct CountedRow {

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      expandsHorizontally: false, expandsVertically: false,
      measure: { sizeThatFits($0, context: context) },
      register: { register(in: $0, context: context) },
      paint: { paint(into: &$0, in: $1, context: context) })
  }

  @MainActor func register(in rect: Rect, context: LayoutContext) {}

  let index: Int
  let height: Float
  let counter: DrawCounter

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
    counter.measured.append(index)
    return Size(width: proposal.width, height: height)
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: LayoutContext) {
    counter.drawn.append(index)
  }
}

private struct RowContent {

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      expandsHorizontally: false, expandsVertically: false,
      measure: { sizeThatFits($0, context: context) },
      register: { register(in: $0, context: context) },
      paint: { paint(into: &$0, in: $1, context: context) })
  }

  @MainActor func register(in rect: Rect, context: LayoutContext) {}

  let height: Float
  let color: Color

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
    Size(width: proposal.width, height: height)
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: LayoutContext) {
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
    let context = LayoutContext(interaction: interaction)
    beginTestFrame(interaction, input: input)
    var list = DrawList()
    let view = ScrollView(
      showsIndicator: true, sticksToBottom: sticksToBottom,
      controller: controller,
      build: { buffer, context in
        let child = FixedContent(size: Size(width: 100, height: 100)).build(
          into: &buffer, context: context.childScope(0))
        return buffer.stack([child], axis: .vertical, context: context)
      })
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &list, in: viewport)
    }
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

    #expect(interaction.scrollState(for: scrollID).offset.y == 15)
    #expect(list.paintSnapshot.first == .pushClip(viewport))
    #expect(list.paintSnapshot.last == .popClip)
  }

  @Test func horizontalWheelRetainsOffsetAndMovesWideContent() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) -> DrawList {
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      let view = ScrollView(
        showsIndicator: true,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 200, height: 20)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
      return list
    }

    _ = frame()
    let list = frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: -15, y: 0)))

    #expect(interaction.scrollState(for: scrollID).offset.x == 15)
    #expect(interaction.scrollState(for: scrollID).limit.x == 100)
    #expect(
      list.paintSnapshot.contains(
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
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(build: { buffer, context in
            let child = FixedContent(size: Size(width: 100, height: 100)).build(
              into: &buffer, context: context.childScope(0))
            return buffer.stack([child], axis: .vertical, context: context)
          }), context: context.keyed(firstID))
        resolvedBuffer.register(resolved, in: firstViewport)
        resolvedBuffer.paint(resolved, into: &list, in: firstViewport)
      }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(build: { buffer, context in
            let child = FixedContent(size: Size(width: 100, height: 100)).build(
              into: &buffer, context: context.childScope(0))
            return buffer.stack([child], axis: .vertical, context: context)
          }), context: context.keyed(secondID))
        resolvedBuffer.register(resolved, in: secondViewport)
        resolvedBuffer.paint(resolved, into: &list, in: secondViewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -15)))
    #expect(interaction.scrollState(for: firstID).offset.y == 15)
    #expect(interaction.scrollState(for: secondID).offset.y == 0)

    frame(InputState(pointerPosition: Point(x: 10, y: 40), scrollDelta: Point(x: 0, y: -25)))
    #expect(interaction.scrollState(for: firstID).offset.y == 15)
    #expect(interaction.scrollState(for: secondID).offset.y == 25)
  }

  @Test func keyboardNavigationRevealsFocusedScrollContent() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(
            showsIndicator: false,
            build: { buffer, context in
              var nodes: [LayoutNode] = []
              for rowOffset in 0..<4 {
                nodes.append(
                  buffer.sizing(
                    buffer.interactive(
                      action: {},
                      content: { buffer, context, _ in
                        return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
                      }, context: context.childScope(rowOffset)), y: .fixed(10), context: context.childScope(rowOffset))
                )
              }
              return buffer.stack(nodes, axis: .vertical, context: context)
            }), context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollState(for: scrollID).offset.y == 0)

    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollState(for: scrollID).offset.y == 10)
  }

  @Test func keyboardNavigationReachesSpacedVirtualizedRows() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(
            data: 0..<5, rowHeight: 10, spacing: 10, showsIndicator: false, controller: controller,
            build: { buffer, context, index in
              return buffer.interactive(
                id: WidgetID("row-\(index)"), action: {},
                content: { buffer, context, _ in
                  return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
                }, context: context)
            }), context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    for index in 1..<5 {
      frame(InputState(commands: [.navigation(.down)]))
      #expect(interaction.selectedLeafID == WidgetID("row-\(index)"))
    }
    frame()
    #expect(interaction.scrollState(for: scrollID).offset.y == 70)
  }

  @Test func keyboardFocusedRowsShowHoverPhase() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let controller = ScrollViewController()
    let listRect = Rect(x: 0, y: 0, width: 100, height: 40)
    let log = PhaseLog()

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(
            data: 0..<4, rowHeight: 10, showsIndicator: false, controller: controller,
            build: { buffer, context, index in
              return buffer.interactive(
                id: WidgetID("row-\(index)"), action: {},
                content: { buffer, context, phase in
                  log.phases[index] = phase
                  return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
                }, context: context)
            }), context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: listRect)
        resolvedBuffer.paint(resolved, into: &list, in: listRect)
      }
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

  @Test func variableRowsUseCachedPositionsAtDistantOffsets() {
    let context = LayoutContext()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    let rows = (0..<1_000).map { index in
      ScrollView.Row(
        id: index,
        build: { buffer, context in
          CountedRow(index: index, height: Float(index % 3 + 1), counter: counter).build(
            into: &buffer, context: context)
        })
    }
    let positions = Interaction.VariableScrollRows(
      keys: [], heights: rows.indices.map { Float($0 % 3 + 1) }, spacing: 2)
    let target = 900
    let viewport = Rect(x: 0, y: 0, width: 100, height: 3)
    let view = ScrollView(spacing: 2, showsIndicator: false, controller: controller, rows: rows)

    func frame() {
      beginTestFrame(context.interaction, input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      context.interaction.endFrame()
    }

    frame()
    #expect(counter.measured.count == rows.count)
    counter.measured = []
    counter.drawn = []
    controller.scroll(to: positions.starts[target])
    frame()
    #expect(counter.measured.isEmpty)
    #expect(counter.drawn == [target, target + 1])
    #expect(controller.lazyStackCache.layout?.position(of: target) == positions.starts[target])
  }

  @Test func keyboardNavigationReachesVariableHeightRowsInBothDirections() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let controller = ScrollViewController()
    let heights: [Float] = [8, 18, 6, 15, 9]
    let rows = heights.enumerated().map { index, height in
      ScrollView.Row(
        id: index,
        build: { buffer, context in
          buffer.interactive(
            id: WidgetID("row-\(index)"), action: {},
            content: { buffer, context, _ in
              return RowContent(height: height, color: .white).build(into: &buffer, context: context)
            }, context: context)
        })
    }

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(spacing: 7, showsIndicator: false, controller: controller, rows: rows),
          context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
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
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let view = ScrollView(
      data: 0..<10, rowHeight: 10, spacing: 5, showsIndicator: false, controller: controller,
      build: { buffer, context, index in
        return buffer.interactive(
          id: WidgetID("row-\(index)"), action: {},
          content: { buffer, context, _ in
            return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
          }, context: context)
      })

    runtime.build = { buffer, context in buffer.scrollView(view, context: context.keyed(scrollID)) }
    func frame(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: viewport.size, input: input,
        onChange: {})
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down), .navigation(.down), .navigation(.down)]))
    #expect(context.interaction.tree?.node(at: context.interaction.selection ?? [])?.rect.minY == 10)
    frame()
    #expect(context.interaction.scrollState(for: scrollID).offset.y == 35)
  }

  @Test func keyboardNavigationRevealsNestedScrollContent() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let outerID = WidgetID("outer-scroll")
    let innerID = WidgetID("inner-scroll")

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(
            showsIndicator: false,
            build: { buffer, context in
              let child = buffer.sizing(
                buffer.scrollView(
                  ScrollView(
                    showsIndicator: false,
                    build: { buffer, context in
                      var nodes: [LayoutNode] = []
                      for (rowOffset, index) in (0..<4).enumerated() {
                        nodes.append(
                          buffer.sizing(
                            buffer.interactive(
                              id: WidgetID("row-\(index)"), action: {},
                              content: { buffer, context, _ in
                                return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
                              }, context: context.childScope(rowOffset)), y: .fixed(10),
                            context: context.childScope(rowOffset)))
                      }
                      return buffer.stack(nodes, axis: .vertical, context: context)
                    }), context: context.childScope(0).keyed(innerID)), y: .fixed(20), context: context.childScope(0))
              return buffer.stack([child], axis: .vertical, context: context)
            }), context: context.keyed(outerID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.selectedLeafID == WidgetID("row-2"))
    #expect(interaction.scrollState(for: innerID).offset.y == 10)
    #expect(interaction.scrollState(for: outerID).offset.y == 0)
  }

  @Test func keyboardNavigationRevealsVirtualizedRows() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(
            data: 0..<10, rowHeight: 10, showsIndicator: false, controller: controller,
            build: { buffer, context, _ in
              return buffer.interactive(
                action: {},
                content: { buffer, context, _ in
                  return RowContent(height: 10, color: .white).build(into: &buffer, context: context)
                }, context: context)
            }), context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    frame(InputState(commands: [.navigation(.down)]))
    frame(InputState(commands: [.navigation(.down)]))
    #expect(interaction.scrollState(for: scrollID).offset.y == 10)
  }

  @Test func controllerScrollsToBottom() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)
    controller.scrollToBottom()
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollState(for: scrollID).offset.y == 80)
  }

  @Test func controllerScrollsOnlyEnoughToRevealRectHorizontally() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame() {
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      let view = ScrollView(
        controller: controller,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 200, height: 20)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    controller.scrollToVisible(Rect(x: 125, y: 0, width: 10, height: 10))
    frame()
    #expect(interaction.scrollState(for: scrollID).offset.x == 35)
  }

  @Test func wheelInputWinsOverPendingRevealRequest() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      let view = ScrollView(
        controller: controller,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 100, height: 100)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    controller.scrollToVisible(Rect(x: 0, y: 25, width: 100, height: 10))
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: 0, y: -12)))
    #expect(interaction.scrollState(for: scrollID).offset.y == 12)
  }

  @Test(arguments: [(false, false), (false, true), (true, false)], ["first", "normal", "reset"])
  func runtimeWheelCancelsPendingRevealRequest(configuration: (Bool, Bool), frameState: String) {
    let (lazy, horizontal) = configuration
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let view: ScrollView =
      lazy
      ? ScrollView(
        data: 0..<100, rowHeight: 10, controller: controller,
        build: { buffer, context, _ in
          return buffer.text(Text("Row"), context: context)
        })
      : ScrollView(
        controller: controller,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 1000, height: 1000)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
    runtime.build = { buffer, context in buffer.scrollView(view, context: context.keyed(scrollID)) }
    func frame(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: viewport.size, input: input,
        onChange: {})
    }

    if frameState != "first" { frame() }
    if frameState == "reset" { runtime.reset() }
    controller.scrollToVisible(Rect(x: 500, y: 500, width: 10, height: 10))
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: horizontal ? Point(x: -12, y: 0) : Point(x: 0, y: -12)))

    #expect(context.interaction.scrollState(for: scrollID).offset.y == (horizontal ? 0 : 12))
    #expect(context.interaction.scrollState(for: scrollID).offset.x == (horizontal ? 12 : 0))
    #expect(controller.request == nil)
    frame()
    #expect(context.interaction.scrollState(for: scrollID).offset.y == (horizontal ? 0 : 12))
    #expect(context.interaction.scrollState(for: scrollID).offset.x == (horizontal ? 12 : 0))
  }

  @Test(arguments: [false, true], ["first", "normal", "reset"])
  func runtimeAppliesExplicitScrollRequestAfterWheel(lazy: Bool, frameState: String) {
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let view: ScrollView =
      lazy
      ? ScrollView(
        data: 0..<100, rowHeight: 10, controller: controller,
        build: { buffer, context, _ in
          return buffer.text(Text("Row"), context: context)
        })
      : ScrollView(
        controller: controller,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 100, height: 1000)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
    runtime.build = { buffer, context in buffer.scrollView(view, context: context.keyed(scrollID)) }
    func frame(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: viewport.size, input: input,
        onChange: {})
    }

    if frameState != "first" { frame() }
    if frameState == "reset" { runtime.reset() }
    controller.scroll(to: 50)
    frame(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -12)))
    #expect(context.interaction.scrollState(for: scrollID).offset.y == 50)
    #expect(controller.request == nil)
  }

  @Test(arguments: [Point.zero, Point(x: 0, y: -12), Point(x: -12, y: 0)])
  func lazyRevealSurvivesUnrelatedWheelInput(delta: Point) {
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let view = ScrollView(
      data: 0..<100, rowHeight: 10, controller: controller,
      build: { buffer, context, _ in
        return buffer.text(Text("Row"), context: context)
      })
    controller.scrollToVisible(Rect(x: 0, y: 500, width: 10, height: 10))
    runtime.build = { buffer, context in buffer.scrollView(view, context: context.keyed(scrollID)) }
    _ = runtime.render(
      viewport: viewport.size,
      input: InputState(
        pointerPosition: delta.y != 0 ? Point(x: 200, y: 200) : Point(x: 10, y: 10),
        scrollDelta: delta),
      onChange: {})
    #expect(context.interaction.scrollState(for: scrollID).offset.y == 490)
    #expect(controller.request == nil)
  }

  @Test(
    arguments: [false, true],
    ["first", "normal", "reset"])
  func clippedRevealRespectsWheelHitTesting(lazy: Bool, frameState: String) {
    for pointer in [Point(x: 10, y: 10), Point(x: 10, y: 50), Point(x: 50, y: 10)] {
      for delta in [Point.zero, Point(x: 0, y: -12), Point(x: -12, y: 0)] {
        let runtime = WindowRuntime()
        let context = runtime.context
        let controller = ScrollViewController()
        let scroll: ScrollView =
          lazy
          ? ScrollView(
            data: 0..<100, rowHeight: 10, controller: controller,
            build: { buffer, context, _ in
              return buffer.text(Text("Row"), context: context)
            })
          : ScrollView(
            controller: controller,
            build: { buffer, context in
              let child = FixedContent(size: Size(width: 1000, height: 1000)).build(
                into: &buffer, context: context.childScope(0))
              return buffer.stack([child], axis: .vertical, context: context)
            })
        runtime.build = { buffer, context in
          ClippedScrollContent(content: scroll).build(into: &buffer, context: context.keyed(scrollID))
        }
        func frame(_ input: InputState = InputState()) {
          _ = runtime.render(
            viewport: Size(width: 100, height: 100),
            input: input, onChange: {})
        }
        if frameState != "first" { frame() }
        if frameState == "reset" { runtime.reset() }
        controller.scrollToVisible(Rect(x: 500, y: 500, width: 10, height: 10))
        frame(InputState(pointerPosition: pointer, scrollDelta: delta))
        let receivesWheel = pointer == Point(x: 10, y: 10) && (delta.y != 0 || (!lazy && delta.x != 0))
        let expectedY: Float = receivesWheel ? -delta.y : 410
        let expectedX: Float = lazy ? 0 : receivesWheel ? -delta.x : 410
        #expect(context.interaction.scrollState(for: scrollID).offset.y == expectedY)
        #expect(context.interaction.scrollState(for: scrollID).offset.x == expectedX)
        #expect(controller.request == nil)
        frame()
        #expect(context.interaction.scrollState(for: scrollID).offset.y == expectedY)
        #expect(context.interaction.scrollState(for: scrollID).offset.x == expectedX)
      }
    }
  }

  @Test func oversizedRevealTargetDoesNotFightHorizontalScrolling() {
    let interaction = Interaction()
    let controller = ScrollViewController()

    func frame(_ input: InputState = InputState()) {
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      let view = ScrollView(
        controller: controller,
        build: { buffer, context in
          let child = FixedContent(size: Size(width: 200, height: 20)).build(
            into: &buffer, context: context.childScope(0))
          return buffer.stack([child], axis: .vertical, context: context)
        })
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
      interaction.endFrame()
    }

    frame()
    frame(
      InputState(
        pointerPosition: Point(x: 10, y: 10),
        scrollDelta: Point(x: -40, y: 0)))
    #expect(interaction.scrollState(for: scrollID).offset.x == 40)

    controller.scrollToVisible(Rect(x: -40, y: 0, width: 200, height: 10))
    frame()
    #expect(interaction.scrollState(for: scrollID).offset.x == 40)
  }

  @Test func controllerScrollsOnlyEnoughToRevealRect() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)

    controller.scrollToVisible(Rect(x: 0, y: 25, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollState(for: scrollID).offset.y == 15)

    controller.scrollToVisible(Rect(x: 0, y: 5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollState(for: scrollID).offset.y == 15)

    controller.scrollToVisible(Rect(x: 0, y: -5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollState(for: scrollID).offset.y == 10)
  }

  @Test func loopRowsStackAndCreateScrollableContent() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    let colors = [
      Color(r: 1, g: 0, b: 0, a: 1),
      Color(r: 0, g: 1, b: 0, a: 1),
      Color(r: 0, g: 0, b: 1, a: 1),
    ]
    let view = ScrollView(
      showsIndicator: true,
      build: { buffer, context in
        var nodes: [LayoutNode] = []
        for (rowOffset, color) in (colors).enumerated() {
          nodes.append(
            RowContent(height: 10, color: color).build(into: &buffer, context: context.childScope(rowOffset)))
        }
        return buffer.stack(nodes, axis: .vertical, context: context)
      })
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &list, in: viewport)
    }
    interaction.endFrame()

    let rowRects = list.paintSnapshot.compactMap { command -> Rect? in
      guard case .fillRect(let rect, let color) = command, colors.contains(color) else { return nil }
      return rect
    }
    #expect(rowRects.map(\.minY) == [0, 10, 20])
    #expect(interaction.scrollState(for: scrollID).limit.y == 10)
  }

  @Test func lazyStackMeasuresRowsOnceAndOnlyDrawsVisibleRows() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    let rows = (0..<10_000).map { index in
      ScrollView.Row(
        id: WidgetID("row-\(index)"),
        build: { buffer, context in
          CountedRow(index: index, height: 10, counter: counter).build(into: &buffer, context: context)
        })
    }

    func frame() {
      let context = LayoutContext(interaction: interaction)
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      let view = ScrollView(controller: controller, rows: rows)
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(view, context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: viewport)
        resolvedBuffer.paint(resolved, into: &list, in: viewport)
      }
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
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      let stack = ScrollView(
        data: data, rowHeight: 10, spacing: spacing,
        controller: controller,
        build: { buffer, context, index in
          return row(index).build(into: &buffer, context: context)
        })
      #expect(built.isEmpty)
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          stack, context: LayoutContext(interaction: interaction).keyed(scrollID))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: width, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: width, height: 20))
      }
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
    #expect(interaction.scrollState(for: scrollID).limit.y == 0)
    frame([][...])
    #expect(built.isEmpty)
  }

  @Test func lazyStackCacheTracksReorderingReplacementAndWidth() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let counter = DrawCounter()

    let retainedRows = (0..<5).map { index in
      ScrollView.Row(
        id: WidgetID("row-\(index)"),
        build: { buffer, context in
          CountedRow(index: index, height: 10, counter: counter).build(into: &buffer, context: context)
        })
    }

    func frame(_ indices: [Int], width: Float = 100) {
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      let rows = indices.map { retainedRows[$0] }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(controller: controller, rows: rows),
          context: LayoutContext(interaction: interaction).keyed(scrollID))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: width, height: 100))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: width, height: 100))
      }
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
    let context = LayoutContext()
    let controller = ScrollViewController()
    let counter = DrawCounter()
    let first = ScrollView.Row(
      id: Int(1),
      build: { buffer, context in
        CountedRow(index: 0, height: 10, counter: counter).build(into: &buffer, context: context)
      })
    let second = ScrollView.Row(
      id: Int64(1),
      build: { buffer, context in
        CountedRow(index: 1, height: 20, counter: counter).build(into: &buffer, context: context)
      })

    func frame(_ rows: [ScrollView.Row]) {
      counter.measured = []
      counter.drawn = []
      beginTestFrame(context.interaction, input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(controller: controller, rows: rows), context: context.keyed(scrollID))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 100))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100))
      }
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
    replacement.build = { buffer, context in
      CountedRow(index: 2, height: 30, counter: counter).build(into: &buffer, context: context)
    }
    frame([second, replacement])
    #expect(counter.measured == [2])
    #expect(controller.lazyStackCache.measurements[0] === measurements[1])
    #expect(controller.lazyStackCache.rowSizes.map(\.height) == [20, 30])
  }

  @Test func scrollInputRespectsClipOnBothAxes() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      interaction.pushClip(Rect(x: 0, y: 0, width: 50, height: 50))
      interaction.registerScrollInput(
        id: scrollID, rect: Rect(x: 0, y: 0, width: 100, height: 100), horizontal: true)
      interaction.scrollStates[scrollID, default: Interaction.ScrollState()].limit = Point(x: 100, y: 100)
      interaction.popClip()
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 75, y: 25), scrollDelta: Point(x: -10, y: -15)))
    #expect(interaction.scrollState(for: scrollID).offset.y == 0)
    #expect(interaction.scrollState(for: scrollID).offset.x == 0)
    frame(InputState(pointerPosition: Point(x: 25, y: 25), scrollDelta: Point(x: -10, y: -15)))
    #expect(interaction.scrollState(for: scrollID).offset.y == 15)
    #expect(interaction.scrollState(for: scrollID).offset.x == 10)
  }

  @Test func clippedLeafCannotBeHitOutsideViewport() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
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
