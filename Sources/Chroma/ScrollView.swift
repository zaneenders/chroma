enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
  case visible(Rect)
}

public final class ScrollViewController {
  var request: ScrollRequest?
  var lazyStackCache = LazyStackCache()

  public init() {}
  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}

struct LazyStackCache {
  var width: Float?
  var rowIDs: [WidgetID] = []
  var rowSizes: [Size] = []
}

public struct ScrollView: PrimitiveBlock {
  public var id: WidgetID
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController?
  public var content: any Block

  public init(
    id: WidgetID,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = VStack(alignment: .leading, content: content)
  }

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    interaction.registerScrollViewport(rect)
    let contentSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: rect.size.width,
        height: Float.greatestFiniteMagnitude
      ), context: context)
    let maximumOffset = max(0, contentSize.height - rect.size.height)
    let maximumHorizontalOffset = max(0, contentSize.width - rect.size.width)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    var horizontalOffset = min(
      interaction.horizontalScrollOffset(for: id), maximumHorizontalOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    let pointerIsInside = rect.contains(interaction.input.pointerPosition)
    let isUserScrolling =
      pointerIsInside
      && (interaction.input.scrollDelta.x != 0 || interaction.input.scrollDelta.y != 0)
    if pointerIsInside {
      offset -= interaction.input.scrollDelta.y
      horizontalOffset -= interaction.input.scrollDelta.x
    }

    for command in interaction.input.semanticCommands {
      switch command {
      case .navigation(.pageUp): offset -= rect.size.height
      case .navigation(.pageDown): offset += rect.size.height
      case .navigation(.home): offset = 0
      case .navigation(.end): offset = maximumOffset
      default: break
      }
    }

    if let request = controller?.request {
      if isUserScrolling, case .visible = request {
        controller?.request = nil
      } else {
        switch request {
        case .top: offset = 0
        case .bottom: offset = maximumOffset
        case .offset(let requested): offset = requested
        case .visible(let target):
          if target.minY < rect.minY {
            offset -= rect.minY - target.minY
          } else if target.maxY > rect.maxY {
            offset += target.maxY - rect.maxY
          }
          if target.size.width <= rect.size.width {
            if target.minX < rect.minX {
              horizontalOffset -= rect.minX - target.minX
            } else if target.maxX > rect.maxX {
              horizontalOffset += target.maxX - rect.maxX
            }
          }
        }
        controller?.request = nil
      }
    } else if sticksToBottom && wasAtBottom && maximumOffset > previousLimit {
      offset = maximumOffset
    }

    offset = min(max(0, offset), maximumOffset)
    horizontalOffset = min(max(0, horizontalOffset), maximumHorizontalOffset)
    interaction.setScrollOffset(offset, for: id)
    interaction.setHorizontalScrollOffset(horizontalOffset, for: id)
    interaction.setScrollLimit(maximumOffset, for: id)
    interaction.setHorizontalScrollLimit(maximumHorizontalOffset, for: id)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX - horizontalOffset, y: rect.minY - offset,
        width: contentSize.width, height: contentSize.height), context: context)
    interaction.popClip()

    let style = context.theme.scrollView
    if showsIndicator && maximumOffset > 0 && rect.size.height > 0 {
      let trackWidth = style.indicatorThickness
      let thumbHeight = max(style.minimumThumbLength, rect.size.height * rect.size.height / contentSize.height)
      let travel = rect.size.height - thumbHeight
      let thumbY = rect.minY + travel * (offset / maximumOffset)
      drawList.fillRect(
        Rect(x: rect.maxX - trackWidth, y: thumbY, width: trackWidth, height: thumbHeight),
        color: style.indicator
      )
    }
    if showsIndicator && maximumHorizontalOffset > 0 && rect.size.width > 0 {
      let trackHeight = style.indicatorThickness
      let thumbWidth = max(style.minimumThumbLength, rect.size.width * rect.size.width / contentSize.width)
      let travel = rect.size.width - thumbWidth
      let thumbX = rect.minX + travel * (horizontalOffset / maximumHorizontalOffset)
      drawList.fillRect(
        Rect(x: thumbX, y: rect.maxY - trackHeight, width: thumbWidth, height: trackHeight),
        color: style.indicator
      )
    }
    drawList.popClip()
  }
}
