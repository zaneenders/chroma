import Observation

enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
  case visible(Rect)
  case row(StructuralKey)
}

@Observable
@MainActor
public final class ScrollViewController {
  @ObservationIgnored public internal(set) var offset: Float = 0
  @ObservationIgnored public internal(set) var horizontalOffset: Float = 0
  @ObservationIgnored private var identity: WidgetID?

  func restore(id: WidgetID, interaction: Interaction) {
    if let identity, identity != id {
      offset = 0
      horizontalOffset = 0
    }
    identity = id
    if interaction.scrollOffsets[id] == nil {
      interaction.setScrollOffset(offset, for: id)
      interaction.setHorizontalScrollOffset(horizontalOffset, for: id)
    }
  }

  var request: ScrollRequest?
  @ObservationIgnored var lazyStackCache = LazyStackCache()

  public init() {}
  public func scrollToRow(_ id: some Hashable & Sendable) { request = .row(StructuralKey(id)) }

  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}
