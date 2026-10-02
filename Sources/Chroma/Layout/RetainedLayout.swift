import Observation
import Synchronization

/// Explicit invalidation for a `CachedLayout` boundary. Observable reads made while
/// building or measuring its content are tracked automatically. Call `invalidate()`
/// when layout depends on unobserved state, including captured values or ambient state.
/// The token owns no blocks, callbacks, or geometry; the window owns bounded caches.
@Observable
@MainActor
public final class LayoutCache {
  private(set) var revision: UInt64 = 0

  public init() {}

  public func invalidate() { revision &+= 1 }
}

/// Opt-in geometry reuse with fresh content and callbacks on every update.
///
/// Keep `cache` stable, and read observable layout dependencies inside `content`.
/// Changes to unobserved layout inputs require `cache.invalidate()`. A callback-only
/// change does not require invalidation. Nested boundaries share their outer cache's
/// invalidation scope. Without a window cache, this behaves like `DeferredBlock`.
public struct CachedLayout<Content: Block>: PrimitiveBlock {
  private let cache: LayoutCache
  private let content: @MainActor () -> Content

  public init(_ cache: LayoutCache, @BlockBuilder content: @escaping @MainActor () -> Content) {
    self.cache = cache
    self.content = content
  }

  public var focusRule: FocusRule { .container }
  public var preservesContentIdentity: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    prepareLayout(context: context).sizeThatFits(proposal)
  }

  @MainActor public func register(in rect: Rect, context: BlockContext) {
    prepareLayout(context: context).register(in: rect)
  }

  @MainActor public func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    prepareLayout(context: context).draw(into: &list, in: rect)
  }
}

extension CachedLayout: LayoutPreparingBlock {
  @MainActor func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    if let scope = context.retainedLayoutScope {
      // Flatten nested boundaries: their invalidation participates in the enclosing
      // reconciliation subscription, avoiding an independent dependency graph.
      scope.trackBoundary(cache)
      _ = cache.revision
      return BlockEngine.resolve(content(), context: context)
    }
    guard let entry = context.retainedLayoutStore?.entry(cache: cache, context: context) else {
      return BlockEngine.resolve(content(), context: context)
    }
    return entry.reconcile { scope in
      _ = cache.revision
      var context = context
      context.retainedLayoutScope = scope
      return BlockEngine.resolve(content(), context: context)
    }
  }

}

/// Only complete root passes sweep ownership. Removed boundaries and replaced roots
/// release geometry and subscriptions, even if the application keeps its token alive.
@MainActor
final class RetainedLayoutStore {
  private struct Key: Hashable {
    var token: ObjectIdentifier
    var path: StructuralPath
  }

  private var entries: [Key: RetainedLayoutEntry] = [:]
  private var visited: Set<Key> = []
  static let boundaryLimit = 64

  var count: Int { entries.count }
  var nodeCount: Int { entries.values.reduce(0) { $0 + $1.nodeCount } }

  func beginPass() { visited.removeAll(keepingCapacity: true) }
  func endPass() { entries = entries.filter { visited.contains($0.key) } }
  func reset() {
    entries.removeAll()
    visited.removeAll()
  }

  func entry(cache: LayoutCache, context: BlockContext) -> RetainedLayoutEntry? {
    let key = Key(token: ObjectIdentifier(cache), path: context.structuralPath)
    if let entry = entries[key] {
      visited.insert(key)
      return entry
    }
    guard entries.count < Self.boundaryLimit else { return nil }
    visited.insert(key)
    let entry = RetainedLayoutEntry(cache: cache)
    entries[key] = entry
    return entry
  }
}

private final class RetainedLayoutValidity: Sendable {
  let valid = Mutex(true)
}

/// One fresh reconciliation scope assigns deterministic slots; its completed
/// type/path/environment signature validates structure before measurement can hit.
/// Additional trees discovered during registration/painting remain conservative.
@MainActor
final class RetainedLayoutScope {
  fileprivate struct Signature: Equatable {
    var type: ObjectIdentifier
    var path: StructuralPath
    var environment: LazyMeasurementEnvironment
    var hoverStyle: HoverStyle?
  }

  fileprivate let entry: RetainedLayoutEntry
  fileprivate var signatures: [Signature] = []
  fileprivate var tokens: [LayoutCache] = []
  fileprivate var sealed = false
  fileprivate var overflow = false

  fileprivate init(entry: RetainedLayoutEntry) { self.entry = entry }

  func trackBoundary(_ cache: LayoutCache) {
    guard !sealed else { return }
    guard tokens.count < RetainedLayoutEntry.nodeLimit else {
      overflow = true
      return
    }
    tokens.append(cache)
  }

  func makeNode(type: Any.Type, context: BlockContext) -> RetainedLayoutNode? {
    guard !sealed else { return nil }
    let index = signatures.count
    guard index < RetainedLayoutEntry.nodeLimit else {
      overflow = true
      return nil
    }
    signatures.append(
      Signature(
        type: ObjectIdentifier(type), path: context.structuralPath,
        environment: LazyMeasurementEnvironment(
          textScale: context.textScale, fontMetrics: context.fontMetrics, theme: context.theme),
        hoverStyle: context.hoverStyle))
    return RetainedLayoutNode(entry: entry, index: index)
  }
}

@Observable
@MainActor
final class RetainedLayoutEntry {
  static let nodeLimit = 256
  static let proposalLimit = 4

  private var invalidationDelivered = false
  @ObservationIgnored private var validity = RetainedLayoutValidity()
  @ObservationIgnored private var subscription: FrameTrackingSubscription?
  @ObservationIgnored private var signature: [RetainedLayoutScope.Signature] = []
  @ObservationIgnored private var tokens: [LayoutCache] = []
  @ObservationIgnored private var nodes: [Int: Geometry] = [:]
  @ObservationIgnored private let cache: LayoutCache
  @ObservationIgnored private var canCache = true

  init(cache: LayoutCache) { self.cache = cache }

  private struct Geometry: Sendable {
    var lifetime: PipelineMetricLifetime?
    var sizes: [(Size, Size, FrameTrackingSubscription)] = []
    var placements: [(Size, [Rect], FrameTrackingSubscription)] = []
    func cancel() {
      for item in sizes { item.2.cancel() }
      for item in placements { item.2.cancel() }
    }
  }

  var nodeCount: Int { nodes.count }

  deinit {
    subscription?.cancel()
    for geometry in nodes.values { geometry.cancel() }
  }

  private func clearGeometry() {
    for geometry in nodes.values { geometry.cancel() }
    nodes.removeAll(keepingCapacity: true)
  }

  func reconcile(_ build: (RetainedLayoutScope) -> BlockEngine.Resolved) -> BlockEngine.Resolved {
    subscription?.cancel()
    // Reading this observable flag keeps cached geometry connected to the frame's
    // redraw subscription. The synchronized bit, not delivery, controls correctness.
    _ = invalidationDelivered
    if !validity.valid.withLock({ $0 }) {
      clearGeometry()
      validity = RetainedLayoutValidity()
      invalidationDelivered = false
    }
    let scope = RetainedLayoutScope(entry: self)
    let (resolved, subscription) = track { build(scope) }
    self.subscription = subscription
    scope.sealed = true
    canCache = !scope.overflow
    if !canCache || signature != scope.signatures
      || tokens.map(ObjectIdentifier.init) != scope.tokens.map(ObjectIdentifier.init)
    {
      clearGeometry()
      signature = scope.signatures
    }
    tokens = scope.tokens
    return resolved
  }

  private func track<Value>(_ compute: () -> Value) -> (Value, FrameTrackingSubscription) {
    let validity = validity
    let subscription = FrameTrackingSubscription(
      { [weak self] in
        guard let self, self.validity === validity else { return }
        self.invalidationDelivered = true
      }, metricsLifetime: PipelineMetrics.trackLifetime(.observationSubscription))
    let enqueue = ObservationDelivery.enqueue
    let result = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      return compute()
    } onChange: { event in
      event.cancel()
      guard let invalidate = subscription.takeCallback() else { return }
      validity.valid.withLock { $0 = false }
      enqueue { invalidate() }
    }
    return (result, subscription)
  }

  fileprivate func measure(_ proposal: Size, at index: Int, compute: () -> Size) -> Size {
    guard canCache else { return compute() }
    _ = invalidationDelivered
    if validity.valid.withLock({ $0 }), let hit = nodes[index]?.sizes.first(where: { $0.0 == proposal }) {
      PipelineMetrics.record(.measurementCacheHit)
      PipelineMetrics.record(.retainedMeasurementHit)
      return hit.1
    }
    let (result, subscription) = track(compute)
    // Nested measurements can populate this same dictionary while computing.
    var geometry = nodes[index] ?? Geometry(lifetime: PipelineMetrics.trackLifetime(.retainedNode))
    if geometry.sizes.count == Self.proposalLimit {
      // Cancellation is observable by enclosing measurements. Conservatively retire
      // this boundary's epoch; the next reconciliation rebuilds its dependencies.
      validity.valid.withLock { $0 = false }
      geometry.sizes.removeFirst().2.cancel()
    }
    geometry.sizes.append((proposal, result, subscription))
    nodes[index] = geometry
    return result
  }

  fileprivate func placement(_ proposal: Size, at index: Int, compute: () -> [Rect]) -> [Rect] {
    guard canCache else { return compute() }
    _ = invalidationDelivered
    if validity.valid.withLock({ $0 }), let hit = nodes[index]?.placements.first(where: { $0.0 == proposal }) {
      PipelineMetrics.record(.retainedPlacementHit)
      return hit.1
    }
    let (result, subscription) = track(compute)
    var geometry = nodes[index] ?? Geometry(lifetime: PipelineMetrics.trackLifetime(.retainedNode))
    if geometry.placements.count == Self.proposalLimit {
      validity.valid.withLock { $0 = false }
      geometry.placements.removeFirst().2.cancel()
    }
    geometry.placements.append((proposal, result, subscription))
    nodes[index] = geometry
    return result
  }
}

@MainActor
struct RetainedLayoutNode {
  fileprivate let entry: RetainedLayoutEntry
  fileprivate let index: Int

  func measure(_ proposal: Size, measure: () -> Size) -> Size {
    entry.measure(proposal, at: index, compute: measure)
  }

  /// Relative rectangles are reusable when a subtree moves without changing size.
  func placement(proposal: Size, compute: () -> [Rect]) -> [Rect] {
    entry.placement(proposal, at: index, compute: compute)
  }
}
