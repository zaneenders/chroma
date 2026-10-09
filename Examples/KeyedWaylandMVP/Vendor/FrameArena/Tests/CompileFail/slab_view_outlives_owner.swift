import FrameArena
@_lifetime(immortal)
func rejected() -> Span<Int> {
    var slab = TrivialSlab<Int>(capacity: 1)
    _ = slab.append(1)
    return slab.view
}
