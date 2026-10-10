import Foundation
import KeyedUI
#if MVP_NATIVE
import WaylandBridge
#endif

final class Model {
    var count = 0
    var items: [UInt64] = [101, 102, 103]
}
final class Demo {
    var ui = UIStore()
    let model = Model()
    var lastTime: Double = 0
    func frame(input: Input = Input(), width: Float = 900, height: Float = 660, dt: Float = 1 / 60, present: (borrowing Span<DrawRect>) -> Void) {
        let model = model
        ui.frame(input: input, dt: dt, build: { frame in
            frame.beginColumn(in: Rect(28, 24, width - 56, 130), gap: 8)
            frame.label(key: 1, "KEYED / SWIFT", extent: 48, color: Color(0.07, 0.12, 0.18), scale: 4)
            frame.label(key: 2, "ONE POOL. SHORT BORROWS. FRESH INPUT.", extent: 30, color: Color(0.055, 0.08, 0.12))
            frame.end()
            frame.beginRow(in: Rect(28, 132, width - 56, 76), gap: 12)
            frame.label(key: 3, "COUNT: \(model.count)", extent: 260, color: Color(0.10, 0.24, 0.29), scale: 3)
            frame.button(key: 4, "+ INCREMENT", extent: 228, color: Color(0.10, 0.34, 0.37)) { model.count += 1 }
            frame.button(key: 5, "RESET", extent: 160) { model.count = 0 }
            frame.end()
            frame.beginRow(in: Rect(28, 232, width - 56, 44), gap: 12)
            frame.button(key: 6, "REVERSE KEYS", extent: 240) { model.items.reverse() }
            frame.button(key: 7, model.items.count == 3 ? "REMOVE 102" : "RESTORE 102", extent: 240) {
                if model.items.contains(102) { model.items.removeAll { $0 == 102 } }
                else { model.items.append(102) }
            }
            frame.end()
            frame.beginColumn(in: Rect(28, 302, width - 56, 220), gap: 12)
            for key in model.items {
                let label = "KEY \(key)"
                frame.button(key: key, label, extent: 58, color: key == 102 ? Color(0.23, 0.18, 0.34) : Color(0.11, 0.17, 0.25), showClicks: true)
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
if args.contains("--benchmark") || args.contains("--benchmark-core") {
    let iterations = Int(option("--frames") ?? "10000") ?? 10000
    guard iterations > 0 && iterations <= 10_000_000 else { fatalError("--frames must be between 1 and 10000000") }
    let probe = AllocationProbe()
    probe?.positiveControl()
    var checksum = 0
    var core = UIStore()
    func buildCore(_ frame: inout UIFrame) {
        frame.beginColumn(in: Rect(0, 0, 800, 600))
        for key: UInt64 in 1...12 { frame.button(key: key, "NODE", extent: 32) }
        frame.end()
    }
    let minimal = args.contains("--benchmark-core")
    for _ in 0..<100 {
        if minimal { core.frame(build: buildCore, present: { checksum &+= $0.count }) }
        else { demo.frame { checksum &+= $0.count } }
    }
    let start = ContinuousClock.now
    let cpuStart = processCPUSeconds()
    probe?.start()
    for _ in 0..<iterations {
        if minimal { core.frame(build: buildCore, present: { checksum &+= $0.count }) }
        else { demo.frame { checksum &+= $0.count } }
    }
    probe?.stop()
    let cpuElapsed = processCPUSeconds() - cpuStart
    let elapsed = start.duration(to: .now)
    print("workload=\(minimal ? "fixed-core" : "demo") frames=\(iterations) elapsed=\(elapsed) cpu_seconds=\(cpuElapsed) checksum=\(checksum) nodes=\(minimal ? core.liveCount : demo.ui.liveCount) slots=\(minimal ? core.slotCount : demo.ui.slotCount) dropped=\(minimal ? core.droppedDraws : demo.ui.droppedDraws)")
    if let probe { probe.printCounts() }
    else { print("allocation counts unavailable; run with the optional Linux interposer") }
} else if args.contains("--cpu") {
    let renderer = CPURenderer(width: 900, height: 660)
    demo.frame { renderer.render($0) }
    let path = option("--screenshot") ?? "preview.ppm"
    try renderer.writePPM(to: path)
    print("CPU preview: \(path)")
} else {
    #if MVP_NATIVE
    let path = option("--screenshot") ?? ""
    let frames = Int32(option("--frames") ?? (args.contains("--egl-smoke") ? "12" : "0")) ?? 0
    let result = "Keyed Swift MVP".withCString { title in
        path.withCString { screenshot in
            var config = WBConfig(width: 900, height: 660, max_frames: frames, title: title, screenshot_path: path.isEmpty ? nil : screenshot)
            let run = args.contains("--egl-smoke") ? wb_run_surfaceless : wb_run
            return run(&config, { context, input in
                guard let context, let input else { return }
                let demo = Unmanaged<Demo>.fromOpaque(context).takeUnretainedValue()
                let event = input.pointee
                let dt = demo.lastTime == 0 ? Float(1.0 / 60.0) : Float(min(0.1, max(0, event.time_seconds - demo.lastTime)))
                demo.lastTime = event.time_seconds
                let snapshot = Input(x: event.pointer_inside != 0 ? event.pointer_x : -1, y: event.pointer_inside != 0 ? event.pointer_y : -1, pressed: event.primary_pressed != 0, released: event.primary_released != 0, tab: event.tab_pressed != 0, activate: event.enter_pressed != 0)
                demo.frame(input: snapshot, width: Float(event.width), height: Float(event.height), dt: dt) { draws in
                    for draw in draws {
                        wb_draw_rect(draw.rect.x, draw.rect.y, draw.rect.width, draw.rect.height, draw.color.r, draw.color.g, draw.color.b, draw.color.a, draw.radius)
                    }
                    wb_flush()
                }
            }, Unmanaged.passUnretained(demo).toOpaque())
        }
    }
    if result != 0 { exit(result) }
    #else
    print("CPU build. Run --cpu --screenshot preview.ppm, or build with MVP_NATIVE=1 for Wayland.")
    #endif
}
