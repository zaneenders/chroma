import Foundation

struct GridCell: Hashable {
  var x: Int
  var y: Int
}

enum Tetromino: CaseIterable {
  case i, o, t, s, z, j, l

  var cells: [GridCell] {
    let coordinates: [(Int, Int)] =
      switch self {
      case .i: [(0, 1), (1, 1), (2, 1), (3, 1)]
      case .o: [(0, 0), (1, 0), (0, 1), (1, 1)]
      case .t: [(1, 0), (0, 1), (1, 1), (2, 1)]
      case .s: [(1, 0), (2, 0), (0, 1), (1, 1)]
      case .z: [(0, 0), (1, 0), (1, 1), (2, 1)]
      case .j: [(0, 0), (0, 1), (1, 1), (2, 1)]
      case .l: [(2, 0), (0, 1), (1, 1), (2, 1)]
      }
    return coordinates.map { GridCell(x: $0.0, y: $0.1) }
  }

  var size: Int { self == .i ? 4 : self == .o ? 2 : 3 }
}

struct FallingPiece {
  var kind: Tetromino
  var rotation = 0
  var x = 3
  var y = 0

  var cells: [GridCell] {
    kind.cells.map { cell in
      var cell = cell
      if kind != .o {
        for _ in 0..<rotation {
          cell = GridCell(x: kind.size - 1 - cell.y, y: cell.x)
        }
      }
      return GridCell(x: cell.x + x, y: cell.y + y)
    }
  }
}

struct FallingBlocksGame {
  static let width = 10
  static let height = 20

  var board = [Tetromino?](repeating: nil, count: width * height)
  var active: FallingPiece
  private(set) var upcoming: [Tetromino]
  private(set) var score = 0
  private(set) var lines = 0
  private(set) var isOver = false

  init() {
    var bag = Tetromino.allCases.shuffled()
    let first = bag.removeFirst()
    active = FallingPiece(kind: first, x: (Self.width - first.size) / 2)
    upcoming = bag
  }

  var level: Int { lines / 10 + 1 }
  var dropInterval: Double { max(0.08, 0.8 * pow(0.8, Double(level - 1))) }

  var ghost: FallingPiece {
    var piece = active
    while fits(shifted(piece, y: 1)) { piece.y += 1 }
    return piece
  }

  func fits(_ piece: FallingPiece) -> Bool {
    piece.cells.allSatisfy { cell in
      cell.x >= 0 && cell.x < Self.width && cell.y >= 0 && cell.y < Self.height
        && board[cell.y * Self.width + cell.x] == nil
    }
  }

  @discardableResult
  mutating func move(x: Int = 0, y: Int = 0) -> Bool {
    let candidate = shifted(active, x: x, y: y)
    guard !isOver, fits(candidate) else { return false }
    active = candidate
    return true
  }

  mutating func rotate() {
    guard !isOver else { return }
    var rotated = active
    rotated.rotation = (rotated.rotation + 1) % 4
    for y in [0, -1, -2] {
      for x in [0, -1, 1, -2, 2] {
        let candidate = shifted(rotated, x: x, y: y)
        if fits(candidate) {
          active = candidate
          return
        }
      }
    }
  }

  mutating func step(softDrop: Bool = false) {
    guard !isOver else { return }
    if move(y: 1) {
      if softDrop { score += 1 }
    } else {
      lock()
    }
  }

  mutating func hardDrop() {
    guard !isOver else { return }
    let landing = ghost
    score += (landing.y - active.y) * 2
    active = landing
    lock()
  }

  private func shifted(_ piece: FallingPiece, x: Int = 0, y: Int = 0) -> FallingPiece {
    var piece = piece
    piece.x += x
    piece.y += y
    return piece
  }

  private mutating func lock() {
    for cell in active.cells { board[cell.y * Self.width + cell.x] = active.kind }
    let remainingRows = (0..<Self.height).map { row in
      Array(board[(row * Self.width)..<((row + 1) * Self.width)])
    }.filter { $0.contains(nil) }
    let cleared = Self.height - remainingRows.count
    score += [0, 100, 300, 500, 800][cleared] * level
    lines += cleared
    board = [Tetromino?](repeating: nil, count: cleared * Self.width) + remainingRows.flatMap { $0 }
    if upcoming.count < 7 { upcoming += Tetromino.allCases.shuffled() }
    let next = upcoming.removeFirst()
    active = FallingPiece(kind: next, x: (Self.width - next.size) / 2)
    isOver = !fits(active)
  }
}
