import Chroma
import DemoImages
import Foundation
import Observation

@MainActor
@Observable
final class PerformanceDemoState {
  enum Palette: String, CaseIterable {
    case neon = "NEON"
    case sunset = "SUNSET"
    case ocean = "OCEAN"
  }

  enum Shape: String, CaseIterable {
    case mixed = "MIXED"
    case rounded = "ROUNDED"
    case outline = "OUTLINE"
  }

  enum Page { case scene, clipboard, font }
  var page: Page = .scene
  var fontSample = "café Ångström naïve façade Český"
  var fontScale: Float = 1
  var inspectedGlyph = "é"
  var pastedText = ""
  var sourceText = "Copy this text — hello from Chroma!"
  let image: ImageResource
  var itemCount: Int
  var speed: Float = 1
  var palette: Palette = .neon
  var shape: Shape = .mixed
  var isPaused = false
  private let clock: @MainActor () -> TimeInterval
  private let startedAt: TimeInterval
  var timeOffset: TimeInterval = 0
  var pauseStartedAt: TimeInterval?
  var burst = 0
  let uuidScrollController = ScrollViewController()
  var identifiers = (1...10_000).map { _ in UUID().uuidString }
  var lastAction = "Ready — choose a control"

  init(
    itemCount: Int,
    clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.clock = clock
    startedAt = clock()
    image = DemoImages.mandelbrot
    self.itemCount = min(20_000, max(100, itemCount))
  }

  func regenerateIdentifiers() {
    identifiers = (1...10_000).map { _ in UUID().uuidString }
    lastAction = "Generated 10,000 new UUIDs"
  }

  func adjustItems(by amount: Int) {
    itemCount = min(20_000, max(100, itemCount + amount))
    lastAction = "Density changed to \(itemCount) shapes"
  }

  func cycleSpeed() {
    speed = speed >= 2 ? 0.5 : speed + 0.5
    lastAction = "Speed: \(speedLabel)"
  }

  func cyclePalette() {
    let values = Palette.allCases
    palette = values[(values.firstIndex(of: palette)! + 1) % values.count]
    lastAction = "Switched to the \(palette.rawValue.lowercased()) palette"
  }

  func cycleShape() {
    let values = Shape.allCases
    shape = values[(values.firstIndex(of: shape)! + 1) % values.count]
    lastAction = "Shape: \(shape.rawValue.lowercased())"
  }

  func togglePaused() {
    let now = clock()
    if let pauseStartedAt {
      timeOffset += now - pauseStartedAt
      self.pauseStartedAt = nil
      isPaused = false
      lastAction = "Animation resumed"
    } else {
      pauseStartedAt = now
      isPaused = true
      lastAction = "Animation paused"
    }
  }

  func triggerBurst() {
    burst &+= 1
    lastAction = "Burst #\(burst) randomized every phase"
  }

  var speedLabel: String {
    speed.formatted(
      .number.locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never).precision(.fractionLength(1))) + "×"
  }

  func elapsedTime(at timestamp: TimeInterval? = nil) -> Float {
    let now = pauseStartedAt ?? timestamp ?? clock()
    return Float(now - startedAt - timeOffset) * speed
  }
}

private let demoSmallText: Float = 0.52
private let demoTitleText: Float = 0.82

private struct PerformanceScene: Block {
  let state: PerformanceDemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Text("CHROMA / RENDER LAB")
            .fontScale(demoTitleText)
            .foregroundColor(theme.accent)
          Spacer()
          Text(state.isPaused ? "● PAUSED" : "● LIVE")
            .fontScale(demoSmallText)
            .foregroundColor(state.isPaused ? .yellow : Color(r: 0.25, g: 0.95, b: 0.55, a: 1))
        }
        .padding(16)
        .background(theme.elevatedSurface)
        .border(theme.border)

        HStack(spacing: 8) {
          Button(state.isPaused ? "Resume" : "Pause", fontScale: demoSmallText) {
            state.togglePaused()
          }
          Button("− 500", fontScale: demoSmallText) {
            state.adjustItems(by: -500)
          }
          Button("+ 500", fontScale: demoSmallText) {
            state.adjustItems(by: 500)
          }
          Button("Speed \(state.speedLabel)", fontScale: demoSmallText) {
            state.cycleSpeed()
          }
          Button(state.palette.rawValue, fontScale: demoSmallText) {
            state.cyclePalette()
          }
          Button(state.shape.rawValue, fontScale: demoSmallText) {
            state.cycleShape()
          }
          Button("Burst!", fontScale: demoSmallText) {
            state.triggerBurst()
          }
          Spacer()
        }
        .padding(10)
        .background(theme.surface)
        .border(theme.border)

        HStack(spacing: 10) {
          VStack(spacing: 10) {
            VStack(spacing: 6) {
              Text("MANDELBROT / 640 × 400 RGBA")
                .fontScale(demoSmallText)
                .foregroundColor(theme.accent)
              Image(state.image, scaling: .contain)
                .sizing(x: .grow, y: .fixed(160))
                .background(theme.background)
            }
            .padding(10)
            .background(theme.surface)
            .border(theme.border)

            ShapeCanvas(state: state)
              .sizing(x: .grow, y: .grow)
              .clipped()
          }
          .sizing(x: .grow, y: .grow)

          UUIDList(state: state)
            .sizing(x: .fixed(330), y: .grow)
        }
        .padding(10)

        HStack(spacing: 12) {
          Text(state.lastAction)
            .fontScale(demoSmallText)
            .foregroundColor(theme.foreground)
          Spacer()
          Text("\(state.itemCount) shapes  •  \(state.palette.rawValue)  •  \(state.shape.rawValue)")
            .fontScale(demoSmallText)
            .foregroundColor(theme.accent)
        }
        .padding(10)
        .background(theme.elevatedSurface)
        .border(theme.border)
      }
      .background(theme.background)
    }
  }
}

private struct UUIDList: Block {
  let state: PerformanceDemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 8) {
        Text("\(state.identifiers.count) UUIDs / SCROLL TEST")
          .fontScale(demoSmallText)
          .foregroundColor(theme.accent)
        Text("Scroll here with the wheel or trackpad.")
          .fontScale(demoSmallText)
          .foregroundColor(theme.secondaryForeground)
        HStack(spacing: 6) {
          Button("Generate", fontScale: demoSmallText) {
            state.regenerateIdentifiers()
          }
          Button("Top", fontScale: demoSmallText) {
            state.uuidScrollController.scrollToTop()
          }
          Button("Bottom", fontScale: demoSmallText) {
            state.uuidScrollController.scrollToBottom()
          }
        }
        LazyVStack(
          data: state.identifiers.indices, rowHeight: 48, spacing: 5,
          controller: state.uuidScrollController
        ) { index in
          VStack(spacing: 3) {
            Text("UUID \(index + 1)")
              .fontScale(demoSmallText)
              .foregroundColor(theme.secondaryForeground)
            Text(state.identifiers[index])
              .fontScale(demoSmallText)
              .foregroundColor(theme.foreground)
          }
          .padding(8)
          .sizing(x: .grow)
          .roundedBackground(theme.elevatedSurface, radius: 4)
        }
        .padding(8)
        .sizing(x: .grow, y: .grow)
        .border(theme.border)
      }
      .padding(10)
      .background(theme.surface)
      .border(theme.border)
    }
  }
}

private struct ShapeCanvas: PrimitiveBlock {
  let state: PerformanceDemoState

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRect(rect, color: Color(r: 0.025, g: 0.035, b: 0.065, a: 1))

    let area = Rect(
      x: rect.minX + 16, y: rect.minY + 16,
      width: max(1, rect.size.width - 32), height: max(1, rect.size.height - 32))
    drawList.pushClip(area)

    let count = state.itemCount
    let columns = max(1, Int(sqrt(Double(count) * Double(area.size.width / area.size.height))))
    let rows = max(1, (count + columns - 1) / columns)
    let cellWidth = area.size.width / Float(columns)
    let cellHeight = area.size.height / Float(rows)
    let frame = context.animationFrame(active: !state.isPaused)
    let elapsed = state.elapsedTime(at: frame.timestamp)
    let burstPhase = Float(state.burst) * 1.731

    for index in 0..<count {
      let column = index % columns
      let row = index / columns
      let phase = elapsed * 1.8 + Float(index) * 0.071 + burstPhase
      let waveX = sin(phase) * cellWidth * 0.22
      let waveY = cos(phase * 0.73 + burstPhase) * cellHeight * 0.22
      let pulse = 0.48 + 0.12 * abs(sin(phase * 0.41))
      let width = max(2, cellWidth * pulse)
      let height = max(2, cellHeight * pulse)
      let shapeRect = Rect(
        x: area.minX + Float(column) * cellWidth + (cellWidth - width) / 2 + waveX,
        y: area.minY + Float(row) * cellHeight + (cellHeight - height) / 2 + waveY,
        width: width, height: height)
      let hue = Float(index % 97) / 97
      let color = color(for: hue, elapsed: elapsed, palette: state.palette)

      switch state.shape {
      case .rounded:
        drawList.fillRoundedRect(shapeRect, radius: min(width, height) * 0.38, color: color)
      case .outline:
        drawList.strokeRect(shapeRect, width: 1, color: color)
      case .mixed:
        if index.isMultiple(of: 3) {
          drawList.fillRoundedRect(shapeRect, radius: min(width, height) * 0.3, color: color)
        } else if index.isMultiple(of: 2) {
          drawList.strokeRect(shapeRect, width: 1, color: color)
        } else {
          drawList.fillRect(shapeRect, color: color)
        }
      }
    }
    drawList.popClip()
  }

  private func color(for hue: Float, elapsed: Float, palette: PerformanceDemoState.Palette) -> Color {
    let phase = hue * 6.283 + elapsed * 0.2
    switch palette {
    case .neon:
      return Color(
        r: 0.25 + 0.7 * abs(sin(phase)),
        g: 0.25 + 0.7 * abs(sin(phase + 2.1)),
        b: 0.25 + 0.7 * abs(sin(phase + 4.2)), a: 0.9)
    case .sunset:
      return Color(
        r: 0.72 + 0.27 * abs(sin(phase)),
        g: 0.14 + 0.42 * abs(sin(phase + 1.7)),
        b: 0.22 + 0.4 * abs(sin(phase + 3.5)), a: 0.92)
    case .ocean:
      return Color(
        r: 0.08 + 0.28 * abs(sin(phase + 4.1)),
        g: 0.38 + 0.52 * abs(sin(phase + 2.0)),
        b: 0.62 + 0.36 * abs(sin(phase)), a: 0.92)
    }
  }
}

struct PerformanceDemo: Block {
  let state: PerformanceDemoState
  var body: some Block {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button(state.page == .scene ? "[Scene]" : "Scene") {
          state.page = .scene
        }
        Button(state.page == .clipboard ? "[Clipboard]" : "Clipboard") {
          state.page = .clipboard
        }
        Button(state.page == .font ? "[Font]" : "Font") {
          state.page = .font
        }
        Spacer()
        Text("hjkl / arrows navigate • Enter select")
          .fontScale(demoSmallText)
      }
      if state.page == .clipboard {
        VStack(spacing: 16) {
          Text("CLIPBOARD")
          Text("Drag to select this text, then copy it to another app.")
            .fontScale(0.65).selectable()
          TextField(
            "Copy source", fontScale: 0.7,
            text: { state.sourceText }, onChange: { state.sourceText = $0 })
          TextField(
            "Paste here…", fontScale: 0.7,
            text: { state.pastedText }, onChange: { state.pastedText = $0 })
          Text("Copy / cut / paste / select all: platform shortcut modifier + C / X / V / A. Escape ends editing.")
            .fontScale(0.55)
          Spacer()
        }.padding(20)
      } else if state.page == .font {
        FontDemo(state: state)
      } else {
        PerformanceScene(state: state)
      }
    }.padding(12)
  }
}
