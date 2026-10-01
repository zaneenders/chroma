import Chroma
import Observation

@Observable @MainActor
final class PlayState {
  enum Phase { case ready, playing, paused, gameOver }
  enum Action { case left, right, rotate, softDrop, hardDrop }

  private(set) var game = FallingBlocksGame()
  private(set) var phase = Phase.ready
  private(set) var bestScore = 0
  let focus = FocusTarget()
  private let automaticallyTicks: Bool
  @ObservationIgnored private var tickTask: Task<Void, Never>?

  init(automaticallyTicks: Bool = true) {
    self.automaticallyTicks = automaticallyTicks
  }

  deinit { tickTask?.cancel() }

  func start() {
    game = FallingBlocksGame()
    phase = .playing
    focus.focus()
    scheduleTick()
  }

  func togglePause() {
    switch phase {
    case .ready, .gameOver: start()
    case .playing: pause()
    case .paused:
      phase = .playing
      focus.focus()
      scheduleTick()
    }
  }

  func pause() {
    guard phase == .playing else { return }
    phase = .paused
    tickTask?.cancel()
    tickTask = nil
  }

  func perform(_ action: Action) {
    guard phase == .playing else { return }
    switch action {
    case .left: game.move(x: -1)
    case .right: game.move(x: 1)
    case .rotate: game.rotate()
    case .softDrop: game.step(softDrop: true)
    case .hardDrop: game.hardDrop()
    }
    updateScore()
    if action == .hardDrop { scheduleTick() }
  }

  func tick() {
    guard phase == .playing else { return }
    game.step()
    updateScore()
    scheduleTick()
  }

  private func updateScore() {
    bestScore = max(bestScore, game.score)
    if game.isOver {
      phase = .gameOver
      tickTask?.cancel()
      tickTask = nil
    }
  }

  private func scheduleTick() {
    tickTask?.cancel()
    tickTask = nil
    guard automaticallyTicks, phase == .playing else { return }
    let interval = game.dropInterval
    tickTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(interval)) } catch { return }
      guard !Task.isCancelled else { return }
      self?.tick()
    }
  }
}
