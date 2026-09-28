extension DrawList {
  public func culled(to viewport: Size) -> DrawList {
    let root = Rect(origin: .zero, size: viewport)
    var clips: [Rect] = []
    let metrics = FontMetrics()
    var result: [DrawCommand] = []
    result.reserveCapacity(commands.count)
    for command in commands {
      let clip = clips.last ?? root
      let bounds: Rect
      switch command {
      case .pushClip(let rect):
        clips.append(clip.intersection(rect) ?? .zero)
        result.append(command)
        continue
      case .popClip:
        _ = clips.popLast()
        result.append(command)
        continue
      case .fillRect(let rect, _), .strokeRect(let rect, _, _),
        .fillRoundedRect(let rect, _, _), .strokeRoundedRect(let rect, _, _, _):
        bounds = Rect(
          x: rect.minX - 1, y: rect.minY - 1,
          width: rect.size.width + 2, height: rect.size.height + 2)
      case .image(let rect, _, _, _): bounds = rect
      case .text(let position, let text, _, let scale):
        guard scale > 0, scale.isFinite else {
          result.append(command)
          continue
        }
        let width =
          Float(max(0, text.count - 1)) * metrics.cellAdvance * scale
          + metrics.glyphWidth * scale
        bounds = Rect(
          x: position.x, y: position.y, width: width,
          height: metrics.glyphHeight * scale)
      }
      if clip.intersection(bounds) != nil { result.append(command) }
    }
    return DrawList(commands: result)
  }
}
