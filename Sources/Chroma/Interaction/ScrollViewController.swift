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
  private let preservesOffsetAcrossIdentities: Bool
  @ObservationIgnored var limit: Point = .zero
  @ObservationIgnored private var identity: WidgetID?

  func restore(id: WidgetID, interaction: Interaction) {
    if let identity, identity != id {
      if preservesOffsetAcrossIdentities {
        if request == nil { request = .offset(offset) }
      } else {
        offset = 0
        horizontalOffset = 0
        limit = .zero
      }
    }
    identity = id
    if interaction.scrollStates[id] == nil {
      interaction.scrollStates[id] = Interaction.ScrollState(offset: Point(x: horizontalOffset, y: offset), limit: limit)
    }
  }

  var request: ScrollRequest?
  @ObservationIgnored var lazyStackCache = LazyStackCache()

  public init(preservesOffsetAcrossIdentities: Bool = false) {
    self.preservesOffsetAcrossIdentities = preservesOffsetAcrossIdentities
  }
  func scrollToRowKey(_ key: StructuralKey) { request = .row(key) }
  public func scrollToRow(_ id: some Hashable & Sendable) { request = .row(StructuralKey(id)) }

  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}
