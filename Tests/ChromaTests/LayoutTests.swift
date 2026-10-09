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

  private struct Host: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      buffer.emit(body, context: context.component(Self.self))
    }

    var showQueue: Bool

    @MainActor var body: some Block {
      VStack(spacing: 0) {
        header
        switch showQueue {
        case true:
          readyWithQueue
        case false:
          readyWithoutQueue
        }
      }
      .background(Color(r: 0, g: 0, b: 0, a: 1))
    }

    @MainActor private var header: some Block {
      Text("HEADER")
        .sizing(y: .fixed(40))
        .sizing(x: .grow)
    }

    @MainActor private var readyWithQueue: some Block {
      VStack(spacing: 0) {
        transcript
        bottomChrome
      }
      .sizing(x: .grow, y: .grow)
    }

    @MainActor private var readyWithoutQueue: some Block {
      VStack(spacing: 0) {
        transcript
        bottomChrome
      }
      .sizing(x: .grow, y: .grow)
    }

    @MainActor private var transcript: some Block {
      Color(r: 0.1, g: 0.1, b: 0.2, a: 1)
        .sizing(x: .grow, y: .grow)
    }

    @MainActor private var bottomChrome: some Block {
      BottomChromeHost(showQueue: showQueue)
    }

    private struct BottomChromeHost: Block {

      @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(body, context: context.component(Self.self))
      }

      var showQueue: Bool

      @MainActor var body: some Block {
        VStack(spacing: 0) {
          if showQueue {
            QueuedTrayHost()
          }
          ComposerHost()
          StatusHost()
        }
        .sizing(x: .grow)
      }
    }

    private struct QueuedTrayHost: Block {

      @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(body, context: context.component(Self.self))
      }

      @MainActor var body: some Block {
        Text("QUEUED (1)")
          .sizing(x: .grow)
          .sizing(y: .fixed(24))
          .background(Color(r: 0.2, g: 0.2, b: 0.3, a: 1))
      }
    }

    private struct ComposerHost: Block {

      @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(body, context: context.component(Self.self))
      }

      @MainActor var body: some Block {
        Text("COMPOSER")
          .sizing(x: .grow)
          .sizing(y: .fixed(36))
          .background(Color(r: 0.15, g: 0.15, b: 0.25, a: 1))
      }
    }

    private struct StatusHost: Block {

      @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(body, context: context.component(Self.self))
      }

      @MainActor var body: some Block {
        Text("STATUS")
          .sizing(x: .grow)
          .sizing(y: .fixed(24))
          .background(Color(r: 0.12, g: 0.12, b: 0.18, a: 1))
      }
    }
  }

  @Test func readyLayoutPinsBottomChromeBelowTranscript() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(Host(showQueue: true), context: context)
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

  @Test func computedPropertyBottomChromeStillStacksChildren() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(ComputedPropertyHost(showQueue: true), context: context)
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
    let context = BlockContext()
    let fitted = Text("fit").sizing()
    let fixed = Text("fixed").sizing(x: .fixed(120), y: .fixed(48))
    let horizontalGrow = Text("grow").sizing(x: .grow)
    let verticalGrow = Text("grow").sizing(y: .grow)

    let fittedTextSize = measureBlock(Text("fit"), proposal: proposal, context: context)
    #expect(measureBlock(fitted, proposal: proposal, context: context) == fittedTextSize)
    #expect(measureBlock(fixed, proposal: proposal, context: context) == Size(width: 120, height: 48))
    #expect(measureBlock(horizontalGrow, proposal: proposal, context: context).width == 400)
    #expect(measureBlock(verticalGrow, proposal: proposal, context: context).height == 300)

    #expect(!blockExpandsHorizontally(fitted))
    #expect(!blockExpandsVertically(fitted))
    #expect(!blockExpandsHorizontally(fixed))
    #expect(!blockExpandsVertically(fixed))
    #expect(blockExpandsHorizontally(horizontalGrow))
    #expect(!blockExpandsVertically(horizontalGrow))
    #expect(!blockExpandsHorizontally(verticalGrow))
    #expect(blockExpandsVertically(verticalGrow))
  }

  @Test func reverseLayoutFlipsStackChildOrder() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    interaction.beginFrame(input: InputState())

    var horizontalList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(
        HStack {
          Text("first")
          Text("second")
        }.reverseLayout(), context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &horizontalList, in: rect)
    }
    interaction.endFrame()
    interaction.beginFrame(input: InputState())

    var verticalList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(
        VStack {
          Text("first")
          Text("second")
        }.reverseLayout(), context: context)
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
    let horizontal = HStack {
      Text("left")
      Spacer()
      Text("right")
    }
    let vertical = VStack {
      Text("top")
      Spacer()
      Text("bottom")
    }
    let proposal = Size(width: 400, height: 300)
    let context = BlockContext()

    #expect(blockExpandsHorizontally(horizontal))
    #expect(!blockExpandsVertically(horizontal))
    #expect(measureBlock(horizontal, proposal: proposal, context: context).height < proposal.height)

    #expect(!blockExpandsHorizontally(vertical))
    #expect(blockExpandsVertically(vertical))
    #expect(measureBlock(vertical, proposal: proposal, context: context).width < proposal.width)
  }
}

private struct ComputedPropertyHost: Block {

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.emit(body, context: context.component(Self.self))
  }

  var showQueue: Bool

  @MainActor var body: some Block {
    VStack(spacing: 0) {
      transcript
      bottomChrome
    }
    .sizing(x: .grow, y: .grow)
  }

  @MainActor private var transcript: some Block {
    Color(r: 0.1, g: 0.1, b: 0.2, a: 1)
      .sizing(x: .grow, y: .grow)
  }

  @MainActor private var bottomChrome: some Block {
    VStack(spacing: 0) {
      if showQueue {
        queuedTray
      }
      composer
      status
    }
    .sizing(x: .grow)
  }

  @MainActor private var queuedTray: some Block {
    Text("QUEUED (1)")
      .sizing(x: .grow)
      .sizing(y: .fixed(24))
  }

  @MainActor private var composer: some Block {
    Text("COMPOSER")
      .sizing(x: .grow)
      .sizing(y: .fixed(36))
  }

  @MainActor private var status: some Block {
    Text("STATUS")
      .sizing(x: .grow)
      .sizing(y: .fixed(24))
  }
}
