import Chroma

@MainActor
public final class InteractionWorkloadCounters {
  public private(set) var rowMeasurements = 0
  public private(set) var blockEvaluations = 0
  public private(set) var rowDraws = 0
  public private(set) var activations = 0
  public private(set) var lastActivatedRow: Int?

  public init() {}
  public func resetDraws() {
    rowDraws = 0
    rowMeasurements = 0
    blockEvaluations = 0
  }
  fileprivate func recordMeasurement() { rowMeasurements += 1 }
  fileprivate func recordEvaluation() { blockEvaluations += 1 }
  fileprivate func recordDraw() { rowDraws += 1 }
  fileprivate func activate(row: Int) {
    activations += 1
    lastActivatedRow = row
  }
}

@MainActor
public struct InteractionWorkload: Block {
  public let count: Int
  public let lazy: Bool
  public let counters: InteractionWorkloadCounters
  public let controller: ScrollViewController

  public init(
    count: Int, lazy: Bool, counters: InteractionWorkloadCounters,
    controller: ScrollViewController = ScrollViewController()
  ) {
    precondition(count > 0)
    self.count = count
    self.lazy = lazy
    self.counters = counters
    self.controller = controller
  }

  @BlockBuilder public var body: some Block {
    let _ = counters.recordEvaluation()
    if lazy {
      ScrollView(data: 0..<count, rowHeight: 28, controller: controller) { index in
        InteractionRow(index: index, counters: counters)
      }
    } else {
      ScrollView(controller: controller) {
        VStack(spacing: 0) {
          ForEach(0..<count, id: \.self) { index in
            InteractionRow(index: index, counters: counters).sizing(y: .fixed(28))
          }
        }
      }
    }
  }
}

private struct InteractionRow: PrimitiveBlock {
  let index: Int
  let counters: InteractionWorkloadCounters
  var focusRule: FocusRule { .control }
  var expandsHorizontally: Bool { true }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    counters.recordMeasurement()
    return Size(width: proposal.width, height: 28)
  }

  @MainActor func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    counters.recordDraw()
    let state = context.buttonState(in: rect) { counters.activate(row: index) }
    list.fillRoundedRect(rect, radius: 3, color: state.hovered ? .yellow : .black)
    list.text("Session \(index)", at: Point(x: rect.minX + 8, y: rect.minY + 6), color: .white, scale: 0.6)
  }
}
