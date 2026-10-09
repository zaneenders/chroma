import FrameArena
func rejected() {
    var arena = FrameArena<Int>()
    let handle = arena.append(1)
    let view = arena.view
    arena.replace(handle, with: 2)
    print(view[0])
}
