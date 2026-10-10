import KeyedUI
func test(_ ui: inout UIStore) -> (() -> Int)? {
 var saved: (() -> Int)?
 ui.frame(build: { _ in }, present: { view in saved = { view.count } })
 return saved
}
