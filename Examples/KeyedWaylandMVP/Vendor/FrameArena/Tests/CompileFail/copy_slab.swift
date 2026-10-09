import FrameArena
func rejected() {
    let slab = TrivialSlab<Int>(capacity: 1)
    let second = copy slab
    print(second.count)
}
