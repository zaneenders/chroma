import Synchronization

// Process-wide IDs are never deliberately reused, even after an owner dies.
// Atomic avoids a global actor requirement; each arena itself is single-owner.
private let nextOwner = Atomic<UInt64>(1)

func newOwnerID() -> UInt64 {
    while true {
        let current = nextOwner.load(ordering: .relaxed)
        precondition(current != UInt64.max, "Arena owner ID exhausted")
        if nextOwner.compareExchange(expected: current, desired: current + 1, ordering: .relaxed).exchanged {
            return current
        }
    }
}

func nextGeneration(_ current: UInt64) -> UInt64 {
    precondition(current != UInt64.max, "Arena generation exhausted")
    return current + 1
}

/// An ordinary, escapable index token. It never retains its arena or payload.
/// Resolve against its original owner and generation before using its index.
public struct FrameHandle<Element: ~Copyable>: Equatable, Sendable {
    let owner: UInt64
    let generation: UInt64
    let index: Int
}

/// Reusable typed storage with deterministic destruction and one unique owner.
/// This owns a UniqueArray; it is not a heterogeneous or nested-payload allocator.
public struct FrameArena<Element: ~Copyable>: ~Copyable {
    private let owner = newOwnerID()
    private var generation: UInt64 = 0
    private var storage = UniqueArray<Element>()

    public init(reserving capacity: Int = 0) {
        precondition(capacity >= 0)
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var capacity: Int { storage.capacity }

    /// The view cannot outlive this borrow, coexist with mutation, or survive reset.
    public var view: Span<Element> {
        @_lifetime(borrow self) get { storage.span }
    }

    public mutating func reserveCapacity(_ minimum: Int) {
        precondition(minimum >= 0)
        storage.reserveCapacity(minimum)
    }

    @discardableResult
    public mutating func append(_ value: consuming Element) -> FrameHandle<Element> {
        let handle = FrameHandle<Element>(owner: owner, generation: generation, index: count)
        storage.append(value)
        return handle
    }

    public func index(of handle: FrameHandle<Element>) -> Int? {
        guard handle.owner == owner, handle.generation == generation,
              handle.index >= 0, handle.index < count else { return nil }
        return handle.index
    }

    @discardableResult
    public mutating func replace(_ handle: FrameHandle<Element>, with value: consuming Element) -> Bool {
        guard let index = index(of: handle) else { return false }
        storage[index] = value
        return true
    }

    /// Releases String/reference/closure ownership now; retains the element buffer.
    public mutating func reset() {
        generation = nextGeneration(generation)
        storage.removeAll()
    }
}
