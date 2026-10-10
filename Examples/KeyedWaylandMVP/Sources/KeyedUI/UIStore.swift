import FrameArena
import Synchronization

private let ownerIDs = Atomic<UInt64>(1)
struct Node {
    var generation: UInt64 = 1
    var key: UInt64 = 0
    var seen: UInt64 = 0
    var live = false
    var rect = Rect(0, 0, 0, 0)
    var color = Color.panel
    var title = ""
    var action: (() -> Void)?
    var interactive = false
    var clicks = 0
    var showsClicks = false
    var hovered = false
    var hover: Float = 0
    var flash: Float = 0
    var fontScale: Float = 2
}
struct Cursor {
    var rect: Rect
    var position: Float = 0
    var gap: Float
    var horizontal: Bool
}
struct Storage: ~Copyable {
    let owner: UInt64
    var epoch: UInt64 = 0
    var nodes = UniqueArray<Node>()
    var keys: [UInt64: Int] = [:]
    var free = UniqueArray<Int>()
    var order = UniqueArray<Int>()
    var cursors = UniqueArray<Cursor>()
    var focused: NodeHandle?
    var pressed: NodeHandle?
    var draws: TrivialSlab<DrawRect>
    var droppedDraws = 0
    init(nodeCapacity: Int, drawCapacity: Int) {
        let id = ownerIDs.wrappingAdd(1, ordering: .relaxed).oldValue
        precondition(id != UInt64.max)
        owner = id
        nodes.reserveCapacity(nodeCapacity); keys.reserveCapacity(nodeCapacity)
        free.reserveCapacity(nodeCapacity); order.reserveCapacity(nodeCapacity); cursors.reserveCapacity(16)
        draws = TrivialSlab(capacity: drawCapacity)
    }
    func handle(_ index: Int) -> NodeHandle { NodeHandle(owner: owner, slot: index, generation: nodes[index].generation) }
    func resolve(_ handle: NodeHandle?) -> Int? {
        guard let handle, handle.owner == owner, handle.slot >= 0, handle.slot < nodes.count,
              nodes[handle.slot].live, nodes[handle.slot].generation == handle.generation else { return nil }
        return handle.slot
    }
    mutating func place(_ extent: Float) -> Rect {
        precondition(!cursors.isEmpty, "Begin a row or column before adding a node")
        let i = cursors.count - 1
        let cursor = cursors[i]
        let result = cursor.horizontal
            ? Rect(cursor.rect.x + cursor.position, cursor.rect.y, extent, cursor.rect.height)
            : Rect(cursor.rect.x, cursor.rect.y + cursor.position, cursor.rect.width, extent)
        cursors[i].position += extent + cursor.gap
        return result
    }
    mutating func declare(key: UInt64, title: String, rect: Rect, color: Color, scale: Float, interactive: Bool, showsClicks: Bool = false, action: (() -> Void)?) -> NodeHandle {
        let index: Int
        if let old = keys[key] { index = old }
        else {
            if !free.isEmpty { index = free.removeLast() }
            else { index = nodes.count; nodes.append(Node()) }
            nodes[index].key = key; nodes[index].live = true; keys[key] = index
        }
        precondition(nodes[index].seen != epoch, "Keys must be unique within a frame")
        nodes[index].seen = epoch
        // Always refresh configuration before input dispatch. Only deliberate state survives.
        nodes[index].rect = rect; nodes[index].title = title; nodes[index].color = color
        nodes[index].showsClicks = showsClicks
        nodes[index].interactive = interactive; nodes[index].action = action; nodes[index].fontScale = scale
        order.append(index)
        return handle(index)
    }
    mutating func finish(input: Input, dt: Float) {
        precondition(cursors.isEmpty, "Every row/column must be ended")
        for i in 0..<nodes.count where nodes[i].live && nodes[i].seen != epoch {
            keys.removeValue(forKey: nodes[i].key)
            let next = nodes[i].generation.addingReportingOverflow(1)
            precondition(!next.overflow)
            nodes[i] = Node(generation: next.partialValue)
            free.append(i) // Assignment above destroys removed callback and string ownership.
        }
        if let i = resolve(focused), !nodes[i].interactive { focused = nil }
        if resolve(focused) == nil { focused = nil }
        if let i = resolve(pressed), !nodes[i].interactive { pressed = nil }
        if resolve(pressed) == nil { pressed = nil }
        var hit: Int?
        for i in order where nodes[i].interactive && nodes[i].rect.contains(x: input.x, y: input.y) { hit = i }
        if input.tab {
            var foundCurrent = focused == nil
            var first: Int?
            var next: Int?
            for i in order where nodes[i].interactive {
                if first == nil { first = i }
                if foundCurrent && next == nil { next = i }
                if handle(i) == focused { foundCurrent = true }
            }
            if let i = next ?? first { focused = handle(i) }
        }
        if input.pressed { pressed = hit.map { handle($0) }; focused = pressed }
        var activated: Int?
        if input.released {
            if let hit, handle(hit) == pressed { activated = hit }
            pressed = nil
        }
        if input.activate, let i = resolve(focused) { activated = i }
        if let i = activated {
            nodes[i].clicks += 1; nodes[i].flash = 1
            // Callbacks must not indirectly reenter the owner (runtime exclusivity).
            // Capture a separate model or weak owner to avoid retaining an owner cycle.
            nodes[i].action?()
        }
        for i in order {
            nodes[i].hovered = hit == i
            let target: Float = hit == i ? 1 : 0
            nodes[i].hover += (target - nodes[i].hover) * min(1, max(0, dt) * 16)
            nodes[i].flash = max(0, nodes[i].flash - max(0, dt) * 3)
        }
    }
    mutating func emit(_ draw: DrawRect) {
        if draws.append(draw) == nil { droppedDraws += 1 }
    }
    mutating func paint() {
        for position in 0..<order.count {
            let i = order[position]
            let node = nodes[i]
            var color = node.color
            let light = node.hover * 0.07 + node.flash * 0.12
            color.r += light; color.g += light; color.b += light
            if focused == handle(i) {
                emit(DrawRect(Rect(node.rect.x - 2, node.rect.y - 2, node.rect.width + 4, node.rect.height + 4), .accent, radius: 9))
            }
            emit(DrawRect(node.rect, color, radius: 7))
            drawText(node.showsClicks ? "\(node.title) / CLICKS \(node.clicks)" : node.title, x: node.rect.x + 12, y: node.rect.y + (node.rect.height - node.fontScale * 7) / 2, scale: node.fontScale, color: .text)
        }
    }
    mutating func drawText(_ text: String, x: Float, y: Float, scale: Float, color: Color) {
        var x = x
        for char in text.utf8 {
            let bits = BitmapFont.bits(char)
            for row in 0..<7 {
                for column in 0..<5 where bits & (UInt64(1) << (row * 5 + column)) != 0 {
                    emit(DrawRect(Rect(x + Float(column) * scale, y + Float(row) * scale, scale, scale), color))
                }
            }
            x += scale * 6
        }
    }
}

/// Persistent uniquely-owned keyed slots. The frame scratch is separate from node state.
public struct UIStore: ~Copyable {
    private var storage: Storage
    public init(nodeCapacity: Int = 128, drawCapacity: Int = 32_768) {
        precondition(nodeCapacity >= 0 && drawCapacity >= 0)
        storage = Storage(nodeCapacity: nodeCapacity, drawCapacity: drawCapacity)
    }
    public var liveCount: Int { storage.keys.count }
    public var slotCount: Int { storage.nodes.count }
    public var droppedDraws: Int { storage.droppedDraws }
    public func state(for handle: NodeHandle) -> NodeState? {
        guard let i = storage.resolve(handle) else { return nil }
        let node = storage.nodes[i]
        return NodeState(key: node.key, clicks: node.clicks, hovered: node.hovered, focused: storage.focused == handle, hoverAnimation: node.hover, rect: node.rect)
    }
    public func handle(for key: UInt64) -> NodeHandle? { storage.keys[key].map { storage.handle($0) } }
    /// Build fresh geometry/actions, remove old keys, dispatch input, then paint and consume.
    /// `present` must synchronously copy/upload anything an asynchronous consumer needs.
    public mutating func frame(input: Input = Input(), dt: Float = 1 / 60, build: (inout UIFrame) -> Void, present: (borrowing Span<DrawRect>) -> Void) {
        precondition(storage.epoch != UInt64.max)
        storage.epoch += 1
        storage.order.removeAll(); storage.cursors.removeAll()
        storage.draws.reset(); storage.droppedDraws = 0
        do {
            var frame = UIFrame(storage: &storage)
            build(&frame)
        }
        storage.finish(input: input, dt: dt)
        storage.paint()
        present(storage.draws.view)
        storage.draws.reset()
    }
}

/// A compiler-enforced nonescaping, unique access to the current build phase.
/// No node borrow is held across appending; handles are checked owner/slot/generation tokens.
public struct UIFrame: ~Copyable, ~Escapable {
    private var storage: MutableRef<Storage>
    @_lifetime(&storage)
    fileprivate init(storage: inout Storage) { self.storage = MutableRef(&storage) }
    public mutating func beginColumn(in rect: Rect, gap: Float = 8) {
        storage.value.cursors.append(Cursor(rect: rect, gap: gap, horizontal: false))
    }
    public mutating func beginRow(in rect: Rect, gap: Float = 8) {
        storage.value.cursors.append(Cursor(rect: rect, gap: gap, horizontal: true))
    }
    public mutating func end() { precondition(!storage.value.cursors.isEmpty); _ = storage.value.cursors.removeLast() }
    @discardableResult
    public mutating func label(key: UInt64, _ title: String, extent: Float = 32, color: Color = .panel, scale: Float = 2) -> NodeHandle {
        let rect = storage.value.place(extent)
        return storage.value.declare(key: key, title: title, rect: rect, color: color, scale: scale, interactive: false, action: nil)
    }
    @discardableResult
    public mutating func button(key: UInt64, _ title: String, extent: Float = 44, color: Color = .panel, showClicks: Bool = false, onClick: (() -> Void)? = nil) -> NodeHandle {
        let rect = storage.value.place(extent)
        return storage.value.declare(key: key, title: title, rect: rect, color: color, scale: 2, interactive: true, showsClicks: showClicks, action: onClick)
    }
}
