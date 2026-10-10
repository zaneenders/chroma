import FrameArena
func rejected() {
    let slab = TrivialSlab<() -> Void>(capacity: 4)
    print(slab.count)
}
