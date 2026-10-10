/// Experimental comparison only: one fixed-capacity allocation, trivial elements.
/// Capacity exhaustion is explicit; it never silently grows or spills to the heap.
/// BitwiseCopyable excludes String, references, and capturing closures.
public struct TrivialSlab<Element: BitwiseCopyable>: ~Copyable {
    private let owner = newOwnerID()
    private var generation: UInt64 = 0
    private let base: UnsafeMutablePointer<Element>?
    public let capacity: Int
    public private(set) var count = 0

    public init(capacity: Int) {
        precondition(capacity >= 0)
        let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        precondition(!bytes.overflow, "Slab byte count overflow")
        self.capacity = capacity
        base = capacity == 0 ? nil : .allocate(capacity: capacity)
    }

    deinit {
        base?.deinitialize(count: count)
        base?.deallocate()
    }

    public var view: Span<Element> {
        @_lifetime(borrow self) get {
            // Safety: allocation stays aligned, bound, initialized and immutable
            // for the full borrow. Mutation/deinit is excluded by this dependency.
            let buffer = UnsafeBufferPointer(start: base, count: count)
            return _overrideLifetime(Span(_unsafeElements: buffer), borrowing: self)
        }
    }

    public mutating func append(_ value: Element) -> FrameHandle<Element>? {
        guard count < capacity else { return nil }
        let handle = FrameHandle<Element>(owner: owner, generation: generation, index: count)
        base!.advanced(by: count).initialize(to: value)
        count += 1
        return handle
    }

    public func index(of handle: FrameHandle<Element>) -> Int? {
        guard handle.owner == owner, handle.generation == generation,
              handle.index >= 0, handle.index < count else { return nil }
        return handle.index
    }

    public mutating func reset() {
        generation = nextGeneration(generation)
        base?.deinitialize(count: count)
        count = 0
    }
}
