import Testing
@testable import Chroma

/// Regression tests for stack layout. TupleBlock overlays its children in one
/// rect; stacks must receive flattened children so bottom chrome stays pinned.
@MainActor
struct LayoutTests {
  private let viewport = Rect(x: 0, y: 0, width: 400, height: 300)

  private func textPositions(in list: DrawList) -> [(String, Float)] {
    list.commands.compactMap { command in
      guard case .text(let position, let text, _, _) = command else { return nil }
      return (text, position.y)
    }
  }

  private struct Host: Block {
    var showQueue: Bool

    @MainActor var body: some Block {
      VStack(spacing: 0, alignment: .leading) {
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
        .frame(height: 40, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @MainActor private var readyWithQueue: some Block {
      VStack(spacing: 0, alignment: .leading) {
        transcript
        bottomChrome
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor private var readyWithoutQueue: some Block {
      VStack(spacing: 0, alignment: .leading) {
        transcript
        bottomChrome
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor private var transcript: some Block {
      Color(r: 0.1, g: 0.1, b: 0.2, a: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor private var bottomChrome: some Block {
      BottomChromeHost(showQueue: showQueue)
    }

    private struct BottomChromeHost: Block {
      var showQueue: Bool

      @MainActor var body: some Block {
        VStack(spacing: 0, alignment: .leading) {
          if showQueue {
            QueuedTrayHost()
          }
          ComposerHost()
          StatusHost()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }

    private struct QueuedTrayHost: Block {
      @MainActor var body: some Block {
        Text("QUEUED (1)")
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .frame(height: 24, alignment: .topLeading)
          .background(Color(r: 0.2, g: 0.2, b: 0.3, a: 1))
      }
    }

    private struct ComposerHost: Block {
      @MainActor var body: some Block {
        Text("COMPOSER")
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .frame(height: 36, alignment: .topLeading)
          .background(Color(r: 0.15, g: 0.15, b: 0.25, a: 1))
      }
    }

    private struct StatusHost: Block {
      @MainActor var body: some Block {
        Text("STATUS")
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .frame(height: 24, alignment: .topLeading)
          .background(Color(r: 0.12, g: 0.12, b: 0.18, a: 1))
      }
    }
  }

  @Test func readyLayoutPinsBottomChromeBelowTranscript() {
    let interaction = Interaction()
    Interaction.current = interaction
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(Host(showQueue: true), into: &list, in: viewport)
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
    // Bottom chrome should live in the lower third, not float in the middle.
    #expect(queuedY! > viewport.size.height * 0.65)
    #expect(statusY! < viewport.size.height)
  }

  @Test func computedPropertyBottomChromeStillStacksChildren() {
    let interaction = Interaction()
    Interaction.current = interaction
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(LegacyHost(showQueue: true), into: &list, in: viewport)
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

    #expect(BlockEngine.expandsHorizontally(horizontal))
    #expect(!BlockEngine.expandsVertically(horizontal))
    #expect(BlockEngine.measure(horizontal, proposal: proposal).height < proposal.height)

    #expect(!BlockEngine.expandsHorizontally(vertical))
    #expect(BlockEngine.expandsVertically(vertical))
    #expect(BlockEngine.measure(vertical, proposal: proposal).width < proposal.width)
  }
}

/// Mirrors the pre-fix ScribeMac pattern: computed properties referenced from
/// another computed property's stack builder.
private struct LegacyHost: Block {
  var showQueue: Bool

  @MainActor var body: some Block {
    VStack(spacing: 0, alignment: .leading) {
      transcript
      bottomChrome
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @MainActor private var transcript: some Block {
    Color(r: 0.1, g: 0.1, b: 0.2, a: 1)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @MainActor private var bottomChrome: some Block {
    VStack(spacing: 0, alignment: .leading) {
      if showQueue {
        queuedTray
      }
      composer
      status
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  @MainActor private var queuedTray: some Block {
    Text("QUEUED (1)")
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: 24, alignment: .topLeading)
  }

  @MainActor private var composer: some Block {
    Text("COMPOSER")
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: 36, alignment: .topLeading)
  }

  @MainActor private var status: some Block {
    Text("STATUS")
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: 24, alignment: .topLeading)
  }
}
