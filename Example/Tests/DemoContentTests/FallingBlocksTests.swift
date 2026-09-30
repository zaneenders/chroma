import Testing

@testable import DemoContent

struct FallingBlocksTests {
  @Test func bagsContainEveryPieceOnce() {
    var game = FallingBlocksGame()
    var pieces = [game.active.kind]
    for _ in 0..<20 {
      game.board = [Tetromino?](repeating: nil, count: 200)
      game.hardDrop()
      pieces.append(game.active.kind)
    }
    for start in stride(from: 0, to: 21, by: 7) {
      #expect(Set(pieces[start..<(start + 7)]) == Set(Tetromino.allCases))
    }
  }

  @Test func movementStopsAtWallsFloorAndOccupiedCells() {
    var game = FallingBlocksGame()
    game.active = FallingPiece(kind: .o, x: 0, y: 18)
    let pastLeft = game.move(x: -1)
    let pastFloor = game.move(y: 1)
    let toRight = game.move(x: 8)
    let pastRight = game.move(x: 1)
    game.board[18 * 10 + 7] = .t
    let intoBlock = game.move(x: -1)
    #expect(!pastLeft && !pastFloor && toRight && !pastRight && !intoBlock)
  }

  @Test func fourRotationsRestoreEveryPiece() {
    for kind in Tetromino.allCases {
      var game = FallingBlocksGame()
      game.active = FallingPiece(kind: kind, x: 3, y: 5)
      let cells = Set(game.active.cells)
      for _ in 0..<4 { game.rotate() }
      #expect(Set(game.active.cells) == cells)
    }
  }

  @Test func rotationKicksAwayFromWallAndFloor() {
    var game = FallingBlocksGame()
    game.active = FallingPiece(kind: .i, rotation: 1, x: -2, y: 3)
    #expect(game.fits(game.active))
    game.rotate()
    #expect(game.active.rotation == 2)
    #expect(game.fits(game.active))
    game.active = FallingPiece(kind: .t, x: 3, y: 18)
    game.rotate()
    #expect(game.active.rotation == 1)
    #expect(game.fits(game.active))
  }

  @Test func blockedRotationLeavesPieceUnchanged() {
    var game = FallingBlocksGame()
    game.active = FallingPiece(kind: .t, x: 3, y: 10)
    game.board = [Tetromino?](repeating: .o, count: 200)
    for cell in game.active.cells { game.board[cell.y * 10 + cell.x] = nil }
    let cells = game.active.cells
    game.rotate()
    #expect(game.active.cells == cells)
  }

  @Test func ghostMatchesHardDropAndAwardsDistancePoints() {
    var game = FallingBlocksGame()
    game.active = FallingPiece(kind: .o, x: 4, y: 0)
    let ghost = game.ghost
    #expect(ghost.y == 18)
    game.hardDrop()
    #expect(game.score == 36)
    #expect(game.board.compactMap { $0 }.count == 4)
    for cell in ghost.cells { #expect(game.board[cell.y * 10 + cell.x] == .o) }
  }

  @Test func clearsFourRowsAndCompactsRemainingBlocks() {
    var game = FallingBlocksGame()
    for y in 16..<20 {
      for x in 0..<10 where x != 5 { game.board[y * 10 + x] = .j }
    }
    game.board[15 * 10] = .s
    game.active = FallingPiece(kind: .i, rotation: 1, x: 3, y: 16)
    game.hardDrop()
    #expect(game.lines == 4)
    #expect(game.score == 800)
    #expect(game.board[19 * 10] == .s)
    #expect(game.board.compactMap { $0 }.count == 1)
  }

  @Test func levelIncreasesAfterTenLinesAndGravityGetsFaster() {
    var game = FallingBlocksGame()
    let initialInterval = game.dropInterval
    for _ in 0..<10 {
      game.board = [Tetromino?](repeating: nil, count: 200)
      for x in 0..<10 where !(3...6).contains(x) { game.board[190 + x] = .o }
      game.active = FallingPiece(kind: .i, x: 3, y: 18)
      game.hardDrop()
    }
    #expect(game.level == 2)
    #expect(game.lines == 10)
    #expect(game.score == 1_000)
    #expect(game.dropInterval < initialInterval)
  }

  @Test func blockedSpawnEndsGameAndIgnoresFurtherInput() {
    var game = FallingBlocksGame()
    for y in 0..<4 {
      for x in 2...7 { game.board[y * 10 + x] = .z }
    }
    game.active = FallingPiece(kind: .o, x: 0, y: 18)
    game.hardDrop()
    #expect(game.isOver)
    let board = game.board
    let score = game.score
    let moved = game.move(x: 1)
    #expect(!moved)
    game.rotate()
    game.step()
    game.hardDrop()
    #expect(game.board == board)
    #expect(game.score == score)
  }

  @Test func softDropAwardsOnePointAndGravityAwardsNone() {
    var game = FallingBlocksGame()
    game.step()
    #expect(game.score == 0)
    game.step(softDrop: true)
    #expect(game.score == 1)
  }
}

@MainActor
struct PlayStateTests {
  @Test func pauseFreezesGravityAndInputAndRestartKeepsBestScore() {
    let state = PlayState(automaticallyTicks: false)
    state.tick()
    #expect(state.phase == .ready)
    state.start()
    state.perform(.hardDrop)
    #expect(state.bestScore > 0)
    let best = state.bestScore
    state.pause()
    let cells = state.game.active.cells
    state.tick()
    state.perform(.left)
    state.perform(.hardDrop)
    #expect(state.game.active.cells == cells)
    state.togglePause()
    state.tick()
    #expect(state.game.active.y == 1)
    state.start()
    #expect(state.game.score == 0)
    #expect(state.game.board.allSatisfy { $0 == nil })
    #expect(state.bestScore == best)
  }

  @Test func switchingScreensPausesWithoutResettingGame() {
    let state = DemoState(automaticallyUpdates: false)
    state.play.start()
    state.play.perform(.hardDrop)
    let board = state.play.game.board
    state.open(.chat)
    #expect(state.play.phase == .paused)
    state.open(.play)
    #expect(state.play.phase == .paused)
    #expect(state.play.game.board == board)
  }

  @Test func gravityRunsAutomaticallyAndPauseCancelsIt() async throws {
    let state = PlayState()
    state.start()
    let deadline = ContinuousClock.now + .seconds(4)
    while state.game.active.y == 0 && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(state.game.active.y > 0)
    state.pause()
    let cells = state.game.active.cells
    try await Task.sleep(for: .seconds(1))
    #expect(state.game.active.cells == cells)
  }

  @Test func runningGameDoesNotRetainItsState() {
    weak var released: PlayState?
    do {
      let state = PlayState()
      released = state
      state.start()
    }
    #expect(released == nil)
  }
}
