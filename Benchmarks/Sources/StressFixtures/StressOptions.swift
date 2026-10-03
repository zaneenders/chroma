public struct StressOptions: Sendable {
  public let configuration: StressConfiguration
  public let samples: Int
  public let warmup: Int

  public static let usage = "--rows 100000 --panes 3 --depth 8 --events 12 --samples 30 --warmup 5"

  public init(arguments: [String]) throws {
    var values = ["--rows": 100_000, "--panes": 3, "--depth": 8, "--events": 12, "--samples": 30, "--warmup": 5]
    var index = 0
    while index < arguments.count {
      let flag = arguments[index]
      guard values[flag] != nil, index + 1 < arguments.count,
        let value = Int(arguments[index + 1]), value >= 0,
        value > 0 || flag == "--depth" || flag == "--warmup"
      else { throw InvalidOption(argument: flag) }
      values[flag] = value
      index += 2
    }
    configuration = StressConfiguration(
      rows: values["--rows"]!, panes: values["--panes"]!, depth: values["--depth"]!, events: values["--events"]!)
    samples = values["--samples"]!
    warmup = values["--warmup"]!
  }

  public struct InvalidOption: Error, CustomStringConvertible {
    public let argument: String
    public var description: String { "Invalid stress option: \(argument). Usage: \(StressOptions.usage)" }
  }
}
