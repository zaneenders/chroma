import KeyedUI
func test(_ ui: inout UIStore) {
 ui.frame(build: { frame in
  frame.beginRow(in: Rect(0,0,100,40))
  frame.button(key: 1, "A") { frame.end() }
  frame.end()
 }, present: { _ in })
}
