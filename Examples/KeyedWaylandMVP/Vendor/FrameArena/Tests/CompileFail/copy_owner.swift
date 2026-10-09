import FrameArena
func rejected() {
    var arena = FrameArena<Int>()
    arena.append(1)
    let second = copy arena
    print(second.count)
}
