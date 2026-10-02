import Chroma
import ChromaTesting

/// Forces the old draw-to-register behavior through the documented compatibility
/// boundary. The additional wrapper is disclosed in the benchmark report; it is
/// not an independently built historical executable.
public struct LegacyRegistrationRoot: PrimitiveBlock {
  public let content: any Block

  public init(_ content: any Block) { self.content = content }

  public var preservesContentIdentity: Bool { true }
  public var focusRule: FocusRule { .container }
  public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  // Intentionally inherits PrimitiveBlock.register's counted compatibility path.
  public func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    BlockEngine.draw(content, into: &list, in: rect, context: context)
  }
}

public enum RegistrationMode: String, Codable, CaseIterable, Sendable {
  case paintFree = "paint-free"
  case cachedLayout = "cached-layout"
  case legacyPaintTraversal = "legacy-paint-traversal"
}

@MainActor
public final class RegistrationFixture {
  public let host: HeadlessHost
  public let controller = ScrollViewController()
  private let layoutCache = LayoutCache()
  public private(set) var actions = 0
  public private(set) var rowConstructions = 0
  public let rowCount: Int

  private struct Item: Identifiable { let id: Int }

  public init(mode: RegistrationMode, rows: Int) {
    precondition(rows > 0)
    rowCount = rows
    host = HeadlessHost(size: Size(width: 480, height: 360))
    let items = (0..<rows).map { Item(id: $0) }
    let controller = controller
    let content = DeferredBlock { [weak self] in
      let capturedActions = self?.actions ?? 0
      return VStack(spacing: 1) {
        Button("Increment") { [weak self] in self?.actions = capturedActions + 1 }
        ScrollView(data: items, rowHeight: 30, spacing: 1, controller: controller) { [weak self] item in
          self?.rowConstructions += 1
          return Button("Session \(item.id)") {}.sizing(x: .grow)
        }
      }
    }
    switch mode {
    case .paintFree: host.content = content
    case .cachedLayout: host.content = CachedLayout(layoutCache) { return content }
    case .legacyPaintTraversal: host.content = LegacyRegistrationRoot(content)
    }
  }

  /// Focuses the fixed header; the virtualized rows remain below it.
  public func selectIncrement() {
    host.sendInput(InputState(commands: [.navigation(.nextFocus)]))
  }

  /// Two events without presentation deliberately capture a different prior value.
  /// Reusing either old action closure fails the postcondition.
  public func activateTwice() {
    let before = actions
    host.sendInput(InputState(commands: [.action(.activate)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    precondition(actions == before + 2, "Coalesced input used a stale callback or replayed an action")
  }

  public func scroll() {
    host.sendInput(
      InputState(pointerPosition: Point(x: 200, y: 180), scrollDelta: Point(x: 0, y: -3)))
  }

  public func invalidateLayout() { layoutCache.invalidate() }

  public func close() { host.close() }
}
