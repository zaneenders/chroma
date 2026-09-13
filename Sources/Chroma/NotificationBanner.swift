@MainActor
package final class NotificationBanner {
  package private(set) var message: String?
  package private(set) var success = false
  package var onChange: (@MainActor () -> Void)?
  private var dismissal: Task<Void, Never>?
  private let producer = FrameProducer()
  private let context = RenderContext()
  private var capturesPointer = false

  package init() {}

  package func show(_ message: String, success: Bool = false, dismissAfter: Double? = nil) {
    dismissal?.cancel()
    dismissal = nil
    self.message = message
    self.success = success
    if let seconds = dismissAfter, seconds.isFinite, seconds >= 0 {
      dismissal = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        self?.dismiss()
      }
    }
    onChange?()
  }

  package func dismiss() {
    dismissal?.cancel()
    dismissal = nil
    message = nil
    onChange?()
  }

  package func bounds(in viewport: Size) -> Rect {
    let width = min(560, max(0, viewport.width - 32))
    let text = BannerText(message ?? "")
    let height = max(
      56,
      text.sizeThatFits(
        Size(width: max(1, width - 100), height: viewport.height), context: context
      ).height + 32)
    return Rect(x: (viewport.width - width) / 2, y: 16, width: width, height: height)
  }

  package func handleInput(_ input: InputState, viewport: Size) -> Bool {
    let inside = message != nil && bounds(in: viewport).contains(input.pointerPosition)
    if input.pointerPressed {
      capturesPointer = message != nil && bounds(in: viewport).contains(input.pointerPressPosition)
    }
    let consumed = capturesPointer || (inside && !input.pointerDown && !input.pointerReleased)
    if consumed { _ = render(viewport: viewport, input: input) }
    if input.pointerReleased { capturesPointer = false }
    return consumed
  }

  package func render(viewport: Size, input: InputState = InputState()) -> DrawList {
    guard let message else { return DrawList() }
    let panel = BannerPanel(message: message, success: success, rect: bounds(in: viewport)) { [weak self] in
      self?.dismiss()
    }
    return producer.render(
      content: ZStack { panel }, viewport: viewport, input: input, context: context,
      onChange: { [weak self] in self?.onChange?() })
  }
}

private struct BannerPanel: PrimitiveBlock {
  let message: String
  let success: Bool
  let rect: Rect
  let dismiss: @MainActor () -> Void

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  func draw(into drawList: inout DrawList, in _: Rect, context: RenderContext) {
    drawList.pushClip(rect)
    defer { drawList.popClip() }
    drawList.fillRoundedRect(rect, radius: 12, color: Color(r: 0.12, g: 0.14, b: 0.18, a: 1))
    drawList.strokeRoundedRect(rect, radius: 12, width: 1, color: .white)
    Text(success ? "+" : "!")
      .foregroundColor(success ? Color(r: 0.3, g: 0.9, b: 0.5, a: 1) : .yellow)
      .draw(into: &drawList, in: Rect(x: rect.minX + 16, y: rect.minY + 16, width: 20, height: 28), context: context)
    BannerText(message).draw(
      into: &drawList,
      in: Rect(
        x: rect.minX + 44, y: rect.minY + 16, width: max(1, rect.size.width - 100), height: rect.size.height - 32),
      context: context)
    Button("x", id: WidgetID("notification.dismiss"), fontScale: 0.65, padding: EdgeInsets(6), action: dismiss)
      .draw(into: &drawList, in: Rect(x: rect.maxX - 40, y: rect.minY + 12, width: 28, height: 28), context: context)
  }
}

private struct BannerText: PrimitiveBlock {
  let message: String
  init(_ message: String) { self.message = message }

  @MainActor func lines(width: Float, context: RenderContext) -> [String] {
    let columns = max(1, Int(width / (context.fontMetrics.cellAdvance * 0.65)))
    var lines = [String]()
    var line = ""
    for character in message {
      if character == "\n" {
        lines.append(line)
        line = ""
      } else {
        if line.count == columns {
          lines.append(line)
          line = ""
        }
        line.append(character)
      }
    }
    lines.append(line)
    return lines
  }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(
      width: proposal.width,
      height: Float(lines(width: proposal.width, context: context).count) * context.fontMetrics.lineAdvance * 0.65)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    for (index, line) in lines(width: rect.size.width, context: context).enumerated() {
      drawList.text(
        line, at: Point(x: rect.minX, y: rect.minY + Float(index) * context.fontMetrics.lineAdvance * 0.65),
        color: .white, scale: 0.65)
    }
  }
}
