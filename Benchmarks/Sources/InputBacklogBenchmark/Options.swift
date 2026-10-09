struct BacklogOptions: Codable, Sendable {
  var workload = "stress"
  var events = 180
  var inputHz = 60
  var axes = 1
  var trials = 3
  var rows = 100_000
  var depth = 8
  var sections = 200

  static let usage = """
    --workload stress|markdown --events 180 --input-hz 60 --axes 1|2 \
    --trials 3 --rows 100000 --depth 8 --sections 200
    """

  init(arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let flag = arguments[index]
      guard index + 1 < arguments.count else { throw InvalidOption(argument: flag) }
      let value = arguments[index + 1]
      if flag == "--workload" {
        guard ["stress", "markdown"].contains(value) else { throw InvalidOption(argument: flag) }
        workload = value
      } else {
        guard let number = Int(value) else { throw InvalidOption(argument: flag) }
        switch flag {
        case "--events" where (1...10_000).contains(number): events = number
        case "--input-hz" where (1...1_000).contains(number): inputHz = number
        case "--axes" where (1...2).contains(number): axes = number
        case "--trials" where (1...20).contains(number): trials = number
        case "--rows" where (1...1_000_000).contains(number): rows = number
        case "--depth" where (0...32).contains(number): depth = number
        case "--sections" where (1...1_000).contains(number): sections = number
        default: throw InvalidOption(argument: flag)
        }
      }
      index += 2
    }
  }

  struct InvalidOption: Error, CustomStringConvertible {
    let argument: String
    var description: String { "Invalid input backlog option: \(argument). \(BacklogOptions.usage)" }
  }
}
