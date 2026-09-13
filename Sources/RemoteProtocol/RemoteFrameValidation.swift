import Chroma

public enum RemoteFrameValidation {
  public static func isValidViewport(_ size: Size) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
      && (2 / size.width).isFinite && (2 / size.height).isFinite
  }

  public static func isValid(viewport: Size, commands: [DrawCommand]) -> Bool {
    guard isValidViewport(viewport) else { return false }
    var depth = 0
    func point(_ p: Point) -> Bool {
      p.x.isFinite && p.y.isFinite
        && (p.x * (2 / viewport.width)).isFinite
        && (p.y * (2 / viewport.height)).isFinite
    }
    func rect(_ r: Rect) -> Bool {
      r.size.width.isFinite && r.size.height.isFinite && r.size.width >= 0 && r.size.height >= 0
        && point(r.origin) && point(Point(x: r.maxX, y: r.maxY))
    }
    func color(_ c: Color) -> Bool { c.r.isFinite && c.g.isFinite && c.b.isFinite && c.a.isFinite }
    func radii(_ r: CornerRadii) -> Bool {
      [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].allSatisfy { $0.isFinite && $0 >= 0 }
    }
    for command in commands {
      switch command {
      case .fillRect(let r, let c):
        guard rect(r), color(c) else { return false }
      case .strokeRect(let r, let width, let c):
        guard rect(r), width.isFinite, width >= 0, color(c) else { return false }
      case .fillRoundedRect(let r, let corners, let c):
        guard rect(r), radii(corners), color(c) else { return false }
      case .strokeRoundedRect(let r, let corners, let width, let c):
        guard rect(r), radii(corners), width.isFinite, width >= 0, color(c) else { return false }
      case .text(let p, let text, let c, let scale):
        guard point(p), color(c), scale.isFinite, scale > 0 else { return false }
        let metrics = FontMetrics()
        let width = Float(text.count) * metrics.cellAdvance * scale + metrics.glyphWidth * scale
        guard rect(Rect(origin: p, size: Size(width: width, height: metrics.glyphHeight * scale))) else {
          return false
        }
      case .image(let r, let image, let scaling, let alignment):
        guard rect(r), alignment.x.isFinite, alignment.y.isFinite else { return false }
        if r.size.width > 0 && r.size.height > 0 {
          guard let destination = scaling.drawRect(sourceSize: image.size, in: r, alignment: alignment),
            rect(destination)
          else { return false }
        }
      case .pushClip(let r):
        guard rect(r) else { return false }
        depth += 1
      case .popClip:
        guard depth > 0 else { return false }
        depth -= 1
      }
    }
    return depth == 0
  }
}
