public struct Rect: Equatable, BitwiseCopyable, Sendable {
    public var x, y, width, height: Float
    public init(_ x: Float, _ y: Float, _ width: Float, _ height: Float) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func contains(x: Float, y: Float) -> Bool {
        width > 0 && height > 0 && x >= self.x && y >= self.y && x < self.x + width && y < self.y + height
    }
}
public struct Color: Equatable, BitwiseCopyable, Sendable {
    public var r, g, b, a: Float
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public static let text = Color(0.86, 0.9, 0.96)
    public static let panel = Color(0.10, 0.14, 0.20)
    public static let accent = Color(0.17, 0.78, 0.73)
}
/// Fixed-size, trivially destructible frame data. Neither pointers nor ARC payloads.
public struct DrawRect: BitwiseCopyable, Sendable {
    public var rect: Rect
    public var color: Color
    public var radius: Float
    public init(_ rect: Rect, _ color: Color, radius: Float = 0) { self.rect = rect; self.color = color; self.radius = radius }
}
public struct Input: Sendable {
    public var x: Float = -1, y: Float = -1
    public var pressed = false, released = false, tab = false, activate = false
    public init(x: Float = -1, y: Float = -1, pressed: Bool = false, released: Bool = false, tab: Bool = false, activate: Bool = false) {
        self.x = x; self.y = y; self.pressed = pressed; self.released = released; self.tab = tab; self.activate = activate
    }
}
public struct NodeHandle: Equatable, Sendable {
    let owner: UInt64
    let slot: Int
    let generation: UInt64
}
public struct NodeState: Sendable {
    public let key: UInt64
    public let clicks: Int
    public let hovered: Bool
    public let focused: Bool
    public let hoverAnimation: Float
    public let rect: Rect
}
