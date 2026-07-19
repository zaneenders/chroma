struct Glyph {
  var rows: [String]
  init(rows: [String] = Array(repeating: "", count: 7)) {
    self.rows = rows
  }
}
