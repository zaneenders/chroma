import Foundation

@MainActor
final class WaylandPointerInput {
  @MainActor
  private struct ScrollSample {
    enum AxisEvent {
      case movement(horizontal: Bool, delta: Float, time: UInt32)
      case stop(horizontal: Bool, time: UInt32)
    }

    var events: [AxisEvent] = []
    var hasMovement = false

    mutating func append(_ event: AxisEvent) {
      if case .movement = event { hasMovement = true }
      events.append(event)
    }

    func apply(to input: InputAccumulator, isFinger: Bool?, now: TimeInterval) {
      // A source-less stop ends the active sequence; source-less motion starts an unknown one.
      if isFinger != nil || hasMovement {
        input.scrollSource(isFinger: isFinger ?? false, hasMovement: hasMovement)
      }
      for event in events {
        switch event {
        case .movement(let horizontal, let delta, let time):
          input.scrollBy(horizontal: horizontal, delta: delta, time: time)
        case .stop(let horizontal, let time):
          input.stopScroll(horizontal: horizontal, time: time, now: now)
        }
      }
    }
  }

  private enum Event {
    case scroll(ScrollSample)
    case action(() -> Void)
  }

  private let input: InputAccumulator
  private let clock: () -> TimeInterval
  private let deliver: () -> Void
  private var usesFrames = false
  private var events: [Event] = []
  private var isFinger: Bool?
  private(set) var deliveryTime: TimeInterval?

  init(
    input: InputAccumulator,
    clock: @escaping () -> TimeInterval,
    deliver: @escaping () -> Void
  ) {
    self.input = input
    self.clock = clock
    self.deliver = deliver
  }

  var hasPendingFrame: Bool { !events.isEmpty || isFinger != nil }

  func configure(version: UInt32) {
    reset()
    usesFrames = version >= 5
  }

  func dispatchPointer(_ action: @escaping () -> Void) {
    if usesFrames {
      events.append(.action(action))
    } else {
      action()
    }
  }

  // Interleaving input splits scroll runs, but never drains an incomplete pointer frame.
  func dispatchOrdered(_ action: @escaping () -> Void) {
    if hasPendingFrame {
      events.append(.action(action))
    } else {
      action()
    }
  }

  func scrollSource(isFinger: Bool) {
    self.isFinger = isFinger
  }

  func scrollBy(horizontal: Bool, delta: Float, time: UInt32) {
    append(.movement(horizontal: horizontal, delta: delta, time: time))
    if !usesFrames { finishFrame() }
  }

  func stopScroll(horizontal: Bool, time: UInt32) {
    append(.stop(horizontal: horizontal, time: time))
    if !usesFrames { finishFrame() }
  }

  private func append(_ event: ScrollSample.AxisEvent) {
    var sample = ScrollSample()
    if case .scroll(let pending)? = events.last {
      sample = pending
      events.removeLast()
    }
    sample.append(event)
    events.append(.scroll(sample))
  }

  func finishFrame() {
    let now = clock()
    let pending = events
    let isFinger = isFinger
    events.removeAll(keepingCapacity: true)
    self.isFinger = nil
    deliveryTime = now
    defer { deliveryTime = nil }
    for event in pending {
      switch event {
      case .scroll(let sample):
        sample.apply(to: input, isFinger: isFinger, now: now)
        deliver()
      case .action(let action):
        action()
      }
    }
  }

  func reset() {
    events.removeAll(keepingCapacity: true)
    isFinger = nil
    input.reset()
  }
}
