import Foundation
import KeyedUI

final class Demo {
    var ui = UIStore()
    var count = 0
    var items: [UInt64] = [101, 102, 103]
    var clicks: [UInt64: Int] = [:]
    func frame(input: Input = Input(), width: Float = 900, height: Float = 660, dt: Float = 1 / 60, present: (borrowing Span<DrawRect>) -> Void) {
        ui.frame(input: input, dt: dt, build: { frame in
            frame.beginColumn(in: Rect(28, 24, width - 56, 130), gap: 8)
            frame.label(key: 1, "KEYED / SWIFT", extent: 48, color: Color(0.07, 0.12, 0.18), scale: 4)
            frame.label(key: 2, "ONE POOL. SHORT BORROWS. FRESH INPUT.", extent: 30, color: Color(0.055, 0.08, 0.12))
            frame.end()
            frame.beginRow(in: Rect(28, 132, width - 56, 76), gap: 12)
            frame.label(key: 3, "COUNT: \(count)", extent: 260, color: Color(0.10, 0.24, 0.29), scale: 3)
            frame.button(key: 4, "+ INCREMENT", extent: 228, color: Color(0.10, 0.34, 0.37)) { self.count += 1 }
            frame.button(key: 5, "RESET", extent: 160) { self.count = 0 }
            frame.end()
            frame.beginRow(in: Rect(28, 232, width - 56, 44), gap: 12)
            frame.button(key: 6, "REVERSE KEYS", extent: 240) { self.items.reverse() }
            frame.button(key: 7, self.items.count == 3 ? "REMOVE 102" : "RESTORE 102", extent: 240) {
                if self.items.contains(102) { self.items.removeAll { $0 == 102 }; self.clicks[102] = nil }
                else { self.items.append(102) }
            }
            frame.end()
            frame.beginColumn(in: Rect(28, 302, width - 56, 220), gap: 12)
            for key in items {
                let label = "KEY \(key) / CLICKS \(clicks[key, default: 0])"
                frame.button(key: key, label, extent: 58, color: key == 102 ? Color(0.23, 0.18, 0.34) : Color(0.11, 0.17, 0.25)) { self.clicks[key, default: 0] += 1 }
            }
            frame.end()
            frame.beginColumn(in: Rect(28, max(548, height - 88), width - 56, 64), gap: 4)
            frame.label(key: 8, "CLICK A KEY. REORDER. STATE FOLLOWS THE KEY.", extent: 28, color: Color(0.055, 0.08, 0.12))
            frame.label(key: 9, "TAB / ENTER: FOCUS + ACTIVATE   ESC: CLOSE", extent: 28, color: Color(0.055, 0.08, 0.12))
            frame.end()
        }, present: present)
    }
}

let args = CommandLine.arguments
func option(_ name: String) -> String? { guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }; return args[i + 1] }
let demo = Demo()
if args.contains("--benchmark") {
    let iterations = Int(option("--frames") ?? "10000") ?? 10000
    for _ in 0..<100 { demo.frame { _ in } }
    let start = ContinuousClock.now
    for _ in 0..<iterations { demo.frame { _ in } }
    let elapsed = start.duration(to: .now)
    print("frames=\(iterations) elapsed=\(elapsed) nodes=\(demo.ui.liveCount) slots=\(demo.ui.slotCount) dropped=\(demo.ui.droppedDraws)")
} else if args.contains("--cpu") || args.contains("--screenshot") {
    let renderer = CPURenderer(width: 900, height: 660)
    demo.frame { renderer.render($0) }
    let path = option("--screenshot") ?? "preview.ppm"
    try renderer.writePPM(to: path)
    print("CPU preview: \(path)")
} else {
    print("CPU build. Run --cpu --screenshot preview.ppm, or build with MVP_NATIVE=1 for Wayland.")
}
