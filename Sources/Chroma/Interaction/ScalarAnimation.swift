struct ScalarAnimation {
  var from: Float
  var target: Float
  var start: Double
  var duration: Double

  func value(at time: Double) -> Float {
    guard duration > 0 else { return target }
    let progress = (time - start) / duration
    if progress <= 0 { return from }
    if progress >= 1 { return target }
    return Float(Double(from) + (Double(target) - Double(from)) * progress)
  }

  func isActive(at time: Double) -> Bool {
    from != target && duration > 0 && (time - start) < duration
  }
}

extension Interaction {
  func animation(_ id: WidgetID, target: Float, duration: Double) -> ScalarAnimation {
    var state =
      animations[id] ?? ScalarAnimation(from: target, target: target, start: animationTime, duration: duration)
    if state.target != target || state.duration != duration {
      state = ScalarAnimation(
        from: state.value(at: animationTime), target: target, start: animationTime, duration: duration)
    }
    return state
  }
}
