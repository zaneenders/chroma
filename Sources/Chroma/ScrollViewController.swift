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
