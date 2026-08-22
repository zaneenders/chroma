import Testing

@testable import Chroma

@MainActor
struct LayoutTests {
  private let viewport = Rect(x: 0, y: 0, width: 400, height: 300)

  private func textPositions(in list: DrawList) -> [(String, Float)] {
    list.commands.compactMap { command in
      guard case .text(let position, let text, _, _, _) = command else { return nil }
      return (text, position.y)
    }
  }

  private struct Host: Block {
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
      @MainActor var body: some Block {
        Text("QUEUED (1)")
          .sizing(x: .grow)
          .sizing(y: .fixed(24))
          .background(Color(r: 0.2, g: 0.2, b: 0.3, a: 1))
      }
    }

    private struct ComposerHost: Block {
      @MainActor var body: some Block {
        Text("COMPOSER")
          .sizing(x: .grow)
          .sizing(y: .fixed(36))
          .background(Color(r: 0.15, g: 0.15, b: 0.25, a: 1))
      }
    }

    private struct StatusHost: Block {
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
    let context = RenderContext(interaction: interaction)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(Host(showQueue: true), into: &list, in: viewport, context: context)
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
    let context = RenderContext(interaction: interaction)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(LegacyHost(showQueue: true), into: &list, in: viewport, context: context)
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
    let context = RenderContext()
    let fitted = Text("fit").sizing()
    let fixed = Text("fixed").sizing(x: .fixed(120), y: .fixed(48))
    let horizontalGrow = Text("grow").sizing(x: .grow)
    let verticalGrow = Text("grow").sizing(y: .grow)

    let fittedTextSize = BlockEngine.measure(Text("fit"), proposal: proposal, context: context)
    #expect(BlockEngine.measure(fitted, proposal: proposal, context: context) == fittedTextSize)
    #expect(BlockEngine.measure(fixed, proposal: proposal, context: context) == Size(width: 120, height: 48))
    #expect(BlockEngine.measure(horizontalGrow, proposal: proposal, context: context).width == 400)
    #expect(BlockEngine.measure(verticalGrow, proposal: proposal, context: context).height == 300)

    #expect(!BlockEngine.expandsHorizontally(fitted))
    #expect(!BlockEngine.expandsVertically(fitted))
    #expect(!BlockEngine.expandsHorizontally(fixed))
    #expect(!BlockEngine.expandsVertically(fixed))
    #expect(BlockEngine.expandsHorizontally(horizontalGrow))
    #expect(!BlockEngine.expandsVertically(horizontalGrow))
    #expect(!BlockEngine.expandsHorizontally(verticalGrow))
    #expect(BlockEngine.expandsVertically(verticalGrow))
  }

  @Test func reverseLayoutFlipsStackChildOrder() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    interaction.beginFrame(input: InputState())

    var horizontalList = DrawList()
    BlockEngine.draw(
      HStack {
        Text("first")
        Text("second")
      }.reverseLayout(),
      into: &horizontalList,
      in: rect,
      context: context
    )
    interaction.endFrame()
    interaction.beginFrame(input: InputState())

    var verticalList = DrawList()
    BlockEngine.draw(
      VStack {
        Text("first")
        Text("second")
      }.reverseLayout(),
      into: &verticalList,
      in: rect,
      context: context
    )
    interaction.endFrame()

    let horizontalText = horizontalList.commands.compactMap { command -> (String, Point)? in
      guard case .text(let position, let text, _, _, _) = command else { return nil }
      return (text, position)
    }
    let verticalText = verticalList.commands.compactMap { command -> (String, Point)? in
      guard case .text(let position, let text, _, _, _) = command else { return nil }
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
    let context = RenderContext()

    #expect(BlockEngine.expandsHorizontally(horizontal))
    #expect(!BlockEngine.expandsVertically(horizontal))
    #expect(BlockEngine.measure(horizontal, proposal: proposal, context: context).height < proposal.height)

    #expect(!BlockEngine.expandsHorizontally(vertical))
    #expect(BlockEngine.expandsVertically(vertical))
    #expect(BlockEngine.measure(vertical, proposal: proposal, context: context).width < proposal.width)
  }
}

private struct LegacyHost: Block {
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
