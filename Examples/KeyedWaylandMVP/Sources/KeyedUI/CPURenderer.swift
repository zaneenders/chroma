import Foundation

/// Deliberately simple reference renderer for deterministic tests and preview files.
public final class CPURenderer {
    public let width: Int, height: Int
    public private(set) var pixels: [UInt8]
    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0 && width <= 8192 && height <= 8192)
        self.width = width; self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 3)
    }
    public func render(_ draws: borrowing Span<DrawRect>) {
        for i in stride(from: 0, to: pixels.count, by: 3) { pixels[i] = 14; pixels[i + 1] = 20; pixels[i + 2] = 30 }
        for draw in draws {
            let r = draw.rect
            guard r.x.isFinite && r.y.isFinite && r.width.isFinite && r.height.isFinite else { continue }
            let x0 = Int(max(0, min(Float(width), r.x.rounded(.down))))
            let y0 = Int(max(0, min(Float(height), r.y.rounded(.down))))
            let x1 = Int(max(0, min(Float(width), (r.x + r.width).rounded(.up))))
            let y1 = Int(max(0, min(Float(height), (r.y + r.height).rounded(.up))))
            guard x1 > x0 && y1 > y0 else { continue }
            let radius = max(0, min(draw.radius, min(r.width, r.height) / 2))
            let alpha = max(0, min(1, draw.color.a))
            let red = max(0, min(1, draw.color.r)) * 255
            let green = max(0, min(1, draw.color.g)) * 255
            let blue = max(0, min(1, draw.color.b)) * 255
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let px = Float(x) + 0.5, py = Float(y) + 0.5
                    let cx = max(r.x + radius, min(r.x + r.width - radius, px))
                    let cy = max(r.y + radius, min(r.y + r.height - radius, py))
                    if (px - cx) * (px - cx) + (py - cy) * (py - cy) > radius * radius { continue }
                    let i = (y * width + x) * 3
                    pixels[i] = UInt8(red * alpha + Float(pixels[i]) * (1 - alpha))
                    pixels[i + 1] = UInt8(green * alpha + Float(pixels[i + 1]) * (1 - alpha))
                    pixels[i + 2] = UInt8(blue * alpha + Float(pixels[i + 2]) * (1 - alpha))
                }
            }
        }
    }
    public func writePPM(to path: String) throws {
        var bytes = Data("P6\n\(width) \(height)\n255\n".utf8)
        bytes.append(contentsOf: pixels)
        try bytes.write(to: URL(fileURLWithPath: path))
    }
}
