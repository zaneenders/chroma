import Chroma

struct DemoButton: Block {
  let label: String
  let action: () -> Void

  var body: some Block {
    ThemeReader { theme in
      Button(
        label,
        id: WidgetID("button:\(label)"),
        fontScale: DemoMetrics.textScale,
        style: theme.button,
        padding: EdgeInsets(leading: 10),
        action: action
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: DemoMetrics.itemHeight, alignment: .leading)
    }
  }
}
