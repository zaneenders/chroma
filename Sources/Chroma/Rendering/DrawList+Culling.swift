extension DrawList {
  public func culled(to viewport: Size) -> DrawList {
    let root = Rect(origin: .zero, size: viewport)
    var clips: [Rect] = []
    var result: [DrawEntry] = []
    result.reserveCapacity(commands.count)
    for command in commands {
      let clip = clips.last ?? root
      switch command {
      case .pushClip(let rect):
        clips.append(clip.intersection(rect) ?? .zero)
        result.append(command)
      case .popClip:
        _ = clips.popLast()
        result.append(command)
      case .quad(let quad):
        let padding = max(1, quad.edgeSoftness)
        let bounds = Rect(
          x: quad.rect.minX - padding, y: quad.rect.minY - padding,
          width: quad.rect.size.width + 2 * padding,
          height: quad.rect.size.height + 2 * padding)
        if clip.intersection(bounds) != nil { result.append(command) }
      }
    }
    return DrawList(commands: result)
  }
}
