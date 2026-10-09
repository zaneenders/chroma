import FrameArena
func rejected() {
    var arena = FrameArena<Int>()
    arena.append(1)
    let view = arena.view
    arena.append(2)
    print(view[0])
}
