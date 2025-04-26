@testable import Chroma

func enableTestLogging(write_to_file: Bool = true) {
  enableLogging(
    file_path: "chroma.log", logLevel: .trace, tracing: false, write_to_file: write_to_file)
  clearLog("chroma.log")
}
