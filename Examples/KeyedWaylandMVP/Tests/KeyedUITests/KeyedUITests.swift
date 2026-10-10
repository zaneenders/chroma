import Testing
@testable import KeyedUI

private func row(_ frame: inout UIFrame, _ keys: [UInt64], action: (() -> Void)? = nil) {
    frame.beginRow(in: Rect(0, 0, 1000, 40), gap: 0)
    for key in keys { frame.button(key: key, "A", extent: 80, onClick: action) }
    frame.end()
}
@Test func stateFollowsKeyAcrossReorder() {
    var ui = UIStore()
    ui.frame(input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1, 2]) }, present: { _ in })
    ui.frame(input: Input(x: 10, y: 10, released: true), build: { row(&$0, [1, 2]) }, present: { _ in })
    let handle = ui.handle(for: 1)!
    #expect(ui.state(for: handle)?.clicks == 1)
    ui.frame(build: { row(&$0, [2, 1]) }, present: { _ in })
    #expect(ui.handle(for: 1) == handle)
    #expect(ui.state(for: handle)?.clicks == 1)
    #expect(ui.state(for: handle)?.rect.x == 80)
    #expect(ui.state(for: handle)?.focused == true)
}
@Test func removalInvalidatesHandlesAndReusesSlots() {
    var ui = UIStore()
    ui.frame(build: { row(&$0, [1]) }, present: { _ in })
    let old = ui.handle(for: 1)!
    ui.frame(build: { _ in }, present: { _ in })
    #expect(ui.state(for: old) == nil)
    ui.frame(build: { row(&$0, [2]) }, present: { _ in })
    #expect(ui.slotCount == 1)
    #expect(ui.handle(for: 2) != old)
    #expect(ui.state(for: old) == nil)
}
@Test func ownerChecksRejectOtherStores() {
    var a = UIStore(), b = UIStore()
    a.frame(build: { row(&$0, [1]) }, present: { _ in })
    b.frame(build: { row(&$0, [1]) }, present: { _ in })
    #expect(b.state(for: a.handle(for: 1)!) == nil)
}
@Test func callbacksAreRefreshedBeforeRelease() {
    var ui = UIStore(), first = 0, second = 0
    ui.frame(input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1], action: { first += 1 }) }, present: { _ in })
    ui.frame(input: Input(x: 10, y: 10, released: true), build: { row(&$0, [1], action: { second += 1 }) }, present: { _ in })
    #expect(first == 0)
    #expect(second == 1)
}
@Test func freshGeometryPreventsPreviousFrameHit() {
    var ui = UIStore(), clicks = 0
    ui.frame(input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1, 2], action: { clicks += 1 }) }, present: { _ in })
    ui.frame(input: Input(x: 10, y: 10, released: true), build: { row(&$0, [2, 1], action: { clicks += 1 }) }, present: { _ in })
    #expect(clicks == 0)
}
@Test func removedPressCannotActivateReplacement() {
    var ui = UIStore(), clicks = 0
    ui.frame(input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1], action: { clicks += 1 }) }, present: { _ in })
    ui.frame(build: { _ in }, present: { _ in })
    ui.frame(input: Input(x: 10, y: 10, released: true), build: { row(&$0, [2], action: { clicks += 1 }) }, present: { _ in })
    #expect(clicks == 0)
}
@Test func removalReleasesCapturingActions() {
    final class Token {}
    weak var released: Token?
    var ui = UIStore()
    do {
        let token = Token(); released = token
        ui.frame(build: { row(&$0, [1], action: { _ = token }) }, present: { _ in })
    }
    #expect(released != nil)
    ui.frame(build: { _ in }, present: { _ in })
    #expect(released == nil)
}
@Test func keyboardFocusCyclesInCurrentOrder() {
    var ui = UIStore()
    ui.frame(input: Input(tab: true), build: { row(&$0, [2, 1]) }, present: { _ in })
    #expect(ui.state(for: ui.handle(for: 2)!)?.focused == true)
    ui.frame(input: Input(tab: true, activate: true), build: { row(&$0, [2, 1]) }, present: { _ in })
    #expect(ui.state(for: ui.handle(for: 1)!)?.clicks == 1)
    ui.frame(input: Input(tab: true), build: { row(&$0, [2, 1]) }, present: { _ in })
    #expect(ui.state(for: ui.handle(for: 2)!)?.focused == true)
}
@Test func boundedDrawOverflowIsReported() {
    var ui = UIStore(drawCapacity: 1)
    var count = 0
    ui.frame(build: { row(&$0, [1]) }, present: { count = $0.count })
    #expect(count == 1)
    #expect(ui.droppedDraws > 0)
}
@Test func repeatedFramesStayBoundedAndRender() {
    var ui = UIStore()
    let renderer = CPURenderer(width: 100, height: 50)
    var count = 0
    for _ in 0..<1000 {
        ui.frame(input: Input(x: 5, y: 5), build: { row(&$0, [1]) }, present: { count = $0.count })
    }
    #expect(ui.slotCount == 1 && ui.liveCount == 1 && ui.droppedDraws == 0)
    #expect(count > 1)
    ui.frame(build: { row(&$0, [1]) }, present: { renderer.render($0) })
    #expect(renderer.pixels[(20 * 100 + 40) * 3] != 14)
    #expect(renderer.pixels[(49 * 100 + 99) * 3] == 14)
}
