/// Programmatic operations accepted by ``ScrollView``. Set a request on a
/// stable controller and it is consumed during the next draw.
public enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
}

/// Reference-type scroll control that can be retained by application state.
/// The view itself also retains its offset in ``Interaction`` by `WidgetID`.
@MainActor
public final class ScrollViewController {
  fileprivate var request: ScrollRequest?

  public init() {}
  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
}

/// A clipped vertical viewport with retained scroll position, wheel/trackpad
/// input, keyboard paging, optional stick-to-bottom, and a position indicator.
///
/// Content is currently measured and drawn in full. This is the non-lazy
/// foundation; collection virtualization should be a separate container so it
/// can construct only rows intersecting the exposed ``viewport``.
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

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let interaction = Interaction.current
    interaction.registerScrollViewport(rect)
    let contentSize = BlockEngine.measure(
      content,
      proposal: Size(width: rect.size.width, height: Float.greatestFiniteMagnitude)
    )
    let maximumOffset = max(0, contentSize.height - rect.size.height)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    // AppKit's positive Y delta means fingers/wheel moved upward: reveal older
    // content by reducing the top-origin content offset.
    if rect.contains(interaction.input.pointerPosition) {
      offset -= interaction.input.scrollDelta.y
    }

    for command in interaction.input.commands {
      switch command {
      case .pageUp: offset -= rect.size.height
      case .pageDown: offset += rect.size.height
      case .home: offset = 0
      case .end: offset = maximumOffset
      default: break
      }
    }

    if let request = controller?.request {
      switch request {
      case .top: offset = 0
      case .bottom: offset = maximumOffset
      case .offset(let requested): offset = requested
      }
      controller?.request = nil
    } else if sticksToBottom && wasAtBottom && maximumOffset > previousLimit {
      offset = maximumOffset
    }

    offset = min(max(0, offset), maximumOffset)
    interaction.setScrollOffset(offset, for: id)
    interaction.setScrollLimit(maximumOffset, for: id)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX, y: rect.minY - offset,
        width: rect.size.width, height: contentSize.height)
    )
    interaction.popClip()

    if showsIndicator && maximumOffset > 0 && rect.size.height > 0 {
      let trackWidth: Float = 3
      let thumbHeight = max(12, rect.size.height * rect.size.height / contentSize.height)
      let travel = rect.size.height - thumbHeight
      let thumbY = rect.minY + travel * (offset / maximumOffset)
      drawList.fillRect(
        Rect(x: rect.maxX - trackWidth, y: thumbY, width: trackWidth, height: thumbHeight),
        color: Color(r: 1, g: 1, b: 1, a: 0.45)
      )
    }
    drawList.popClip()
  }
}
