import FrameArena
func rejected() {
    var arena = TrivialSlab<Int>(capacity: 4)
    _ = arena.append(1)
    let view = arena.view
    arena.reset()
    print(view[0])
}
