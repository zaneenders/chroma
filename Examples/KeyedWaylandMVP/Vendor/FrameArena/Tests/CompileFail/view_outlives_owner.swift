import FrameArena
@_lifetime(immortal)
func rejected() -> Span<Int> {
    var arena = FrameArena<Int>()
    arena.append(1)
    return arena.view
}
