public struct Text: PaintableBlock {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
  public var wraps = false
  var selectionID: WidgetID?

  public var focusRule: FocusRule { .standard }

  public init(_ content: String) {
    self.content = content
    self.color = .white
    self.scale = 1
  }

  public func foregroundColor(_ color: Color) -> Text {
    var copy = self
    copy.color = color
    return copy
  }

  public func fontScale(_ scale: Float) -> Text {
    var copy = self
    copy.scale = scale
    return copy
  }

  public func selectable() -> Text {
    selectable(nil)
  }

  func selectable(_ id: WidgetID?) -> Text {
    var copy = self
    copy.isSelectable = true
    copy.selectionID = id
    return copy
  }

  public func wrapping(_ enabled: Bool = true) -> Text {
    var copy = self
    copy.wraps = enabled
    return copy
  }

  @MainActor private func columns(width: Float, context: BlockContext) -> Int? {
    let cell = context.fontMetrics.cellAdvance * scale * context.textScale
    guard wraps, width.isFinite, cell.isFinite, cell > 0 else { return nil }
    return Int(min(Float(Int32.max), max(1, width / cell)))
  }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    sizeThatFits(proposal, context: context, preparation: TextLayoutPreparation())
  }

  @MainActor private func sizeThatFits(
    _ proposal: Size, context: BlockContext, preparation: TextLayoutPreparation
  ) -> Size {
    guard wraps else {
      return context.fontMetrics.measure(content, scale: scale * context.textScale)
    }
    let layout = preparation.resolve(content, columns: columns(width: proposal.width, context: context)).layout
    return Size(
      width: proposal.width,
      height: Float(layout.lines.count) * context.fontMetrics.lineAdvance * scale * context.textScale)
  }

  public func register(in rect: Rect, context: BlockContext) {
    if isSelectable {
      registerSelection(prepareText(in: rect, context: context, preparation: TextLayoutPreparation()), context: context)
    }
  }

  @MainActor private func prepareText(
    in rect: Rect, context: BlockContext, preparation: TextLayoutPreparation
  ) -> PlainTextLayout {
    let effectiveScale = scale * context.textScale
    let metrics = context.fontMetrics
    let columns = columns(width: rect.size.width, context: context)
    return PlainTextLayout(
      text: content, rect: rect, cellWidth: metrics.cellAdvance * effectiveScale,
      lineHeight: metrics.lineAdvance * effectiveScale, scale: effectiveScale, columns: columns,
      snapshot: preparation.resolve(content, columns: columns))
  }

  @MainActor private func registerSelection(_ layout: PlainTextLayout, context: BlockContext) {
    let id = selectionID ?? context.widgetID
    let interaction = context.interaction
    interaction.textSelection.layoutRegistry.register(id, layout: layout)
    if !context.focusLeafClaimed, !context.navigationIgnored {
      interaction.registerFocusTargets(context.focusTargets, id: id)
      _ = interaction.registerTextInput(
        id: id, rect: layout.rect, text: { content }, onChange: { _ in },
        pointerOffset: { point, _ in layout.hitTest(point: point) ?? 0 },
        verticalOffset: { layout.verticalOffset($0, direction: $1) }, readOnly: true)
    }
  }

  @MainActor private func selectionVisualState(context: BlockContext) -> (range: Range<Int>?, caret: Int?) {
    let id = selectionID ?? context.widgetID
    var range: Range<Int>?
    var caret: Int?
    if !context.focusLeafClaimed, !context.navigationIgnored {
      let state = context.textInputVisualState(id: id)
      range = state.selectionRange
      caret = state.caretOffset
    }
    if range == nil, let selection = context.interaction.textSelection.selection(for: id) {
      range = selection.from..<selection.to
    }
    return (range, caret)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    if !wraps, !isSelectable {
      paint(into: &drawList, in: rect, context: context)
      return
    }
    let prepared = prepareText(in: rect, context: context, preparation: TextLayoutPreparation())
    if isSelectable {
      registerSelection(prepared, context: context)
      if !context.focusLeafClaimed, !context.navigationIgnored {
        BlockEngine.drawHighlight(
          for: selectionID ?? context.widgetID, into: &drawList, in: rect, context: context)
      }
    }
    paint(prepared, into: &drawList, in: rect, context: context)
  }

  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    if !wraps, !isSelectable {
      PipelineMetrics.record(.textLayout)
      drawText(
        into: &drawList, in: rect, color: color, scale: scale * context.textScale,
        context: context, layout: TextLayout(content))
      return
    }
    paint(
      prepareText(in: rect, context: context, preparation: TextLayoutPreparation()),
      into: &drawList, in: rect, context: context)
  }

  @MainActor private func paint(
    _ layout: PlainTextLayout, into drawList: inout DrawList, in rect: Rect, context: BlockContext
  ) {
    let effectiveScale = scale * context.textScale
    if isSelectable {
      let cellWidth = layout.cellWidth
      let lineHeight = layout.lineHeight
      let (range, caret) = selectionVisualState(context: context)
      drawText(
        into: &drawList, in: rect, color: color, scale: effectiveScale, context: context, layout: layout.layout)
      if let range, !range.isEmpty {
        for line in layout.layout.lines {
          let start = line.range.lowerBound
          let end = line.range.upperBound
          let lower = max(start, range.lowerBound)
          let upper = min(end, range.upperBound)
          if lower < upper {
            let origin = layout.position(at: lower)
            let highlight = Rect(
              x: origin.x, y: origin.y,
              width: Float(upper - lower) * cellWidth, height: lineHeight)
            drawList.fillRect(highlight, color: context.theme.focus.selectionBackground)
            drawList.pushClip(highlight)
            drawText(
              into: &drawList, in: rect, color: context.theme.focus.selectionForeground, scale: effectiveScale,
              context: context, layout: layout.layout)
            drawList.popClip()
          }
        }
      } else if let caret {
        let point = layout.position(at: caret)
        let caretRect = Rect(x: point.x, y: point.y, width: 1, height: lineHeight)
        drawList.fillRect(caretRect, color: context.theme.focus.ring)
      }
      return
    }
    drawText(
      into: &drawList, in: rect, color: color, scale: effectiveScale, context: context, layout: layout.layout)
  }
  @MainActor private func drawText(
    into drawList: inout DrawList, in rect: Rect, color: Color, scale: Float, context: BlockContext,
    layout: TextLayout
  ) {
    for (row, line) in layout.lines.enumerated() {
      drawList.text(
        line.text,
        at: Point(
          x: rect.minX,
          y: rect.minY + Float(row) * context.fontMetrics.lineAdvance * scale), color: color, scale: scale)
    }
  }

}

extension Text: LayoutPreparingBlock {
  public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    if !wraps, !isSelectable {
      return BlockEngine.Resolved(
        expandsHorizontally: { false }, expandsVertically: { false },
        measure: { _ in context.fontMetrics.measure(content, scale: scale * context.textScale) },
        register: { rect in
          if context.interaction.builderStack.last != nil, !context.focusLeafClaimed, !context.navigationIgnored {
            context.registerFocusable(in: rect)
          }
        },
        paint: { list, rect in
          paint(into: &list, in: rect, context: context)
          if !context.focusLeafClaimed, !context.navigationIgnored {
            BlockEngine.drawHighlight(
              for: selectionID ?? context.widgetID, into: &list, in: rect, context: context)
          }
        },
        draw: { BlockEngine.drawResolved(self, into: &$0, in: $1, context: context) })
    }
    let preparation = TextLayoutPreparation()
    return BlockEngine.Resolved(
      expandsHorizontally: { false }, expandsVertically: { false },
      measure: { proposal in sizeThatFits(proposal, context: context, preparation: preparation) },
      register: { rect in
        if isSelectable {
          registerSelection(prepareText(in: rect, context: context, preparation: preparation), context: context)
        } else if context.interaction.builderStack.last != nil, !context.focusLeafClaimed, !context.navigationIgnored {
          context.registerFocusable(in: rect)
        }
      },
      paint: { list, rect in
        if isSelectable, !context.focusLeafClaimed, !context.navigationIgnored {
          BlockEngine.drawHighlight(
            for: selectionID ?? context.widgetID, into: &list, in: rect, context: context)
        }
        paint(
          prepareText(in: rect, context: context, preparation: preparation), into: &list, in: rect, context: context)
        if !isSelectable, !context.focusLeafClaimed, !context.navigationIgnored {
          BlockEngine.drawHighlight(
            for: selectionID ?? context.widgetID, into: &list, in: rect, context: context)
        }
      },
      draw: { list, rect in
        let prepared = prepareText(in: rect, context: context, preparation: preparation)
        if isSelectable {
          registerSelection(prepared, context: context)
          if !context.focusLeafClaimed, !context.navigationIgnored {
            BlockEngine.drawHighlight(
              for: selectionID ?? context.widgetID, into: &list, in: rect, context: context)
          }
        }
        paint(prepared, into: &list, in: rect, context: context)
        if !isSelectable, context.interaction.builderStack.last != nil,
          !context.focusLeafClaimed, !context.navigationIgnored
        {
          context.focusable(in: rect, into: &list)
        }
      })
  }
}
