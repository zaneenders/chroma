import Foundation
import Testing

@testable import ChromaInstaller

struct InstallOptionsTests {
  @Test func defaultsPreservePositionalArgumentsAndProfiling() throws {
    let options = try InstallOptions(arguments: ["/package", "Demo", "/build/Demo"])
    #expect(options.positionalArguments == ["/package", "Demo", "/build/Demo"])
    #expect(options.profiling)
    #expect(options.installDirectory == nil)
  }

  @Test(arguments: [
    ["--install-directory", "/Applications"],
    ["--install-directory", "/Applications", "--without-profiling"],
    ["--without-profiling", "--install-directory", "/Applications"],
    ["--install-directory", "/private/tmp/test apps"],
  ])
  func acceptsDirectoryWithAndWithoutProfiling(flags: [String]) throws {
    let options = try InstallOptions(arguments: ["/package", "Demo"] + flags)
    let directoryIndex = try #require(flags.firstIndex(of: "--install-directory")) + 1
    #expect(options.installDirectory?.path == flags[directoryIndex])
    #expect(options.profiling == !flags.contains("--without-profiling"))
    #expect(options.positionalArguments == ["/package", "Demo"])
  }

  @Test(arguments: [
    ["--install-directory"],
    ["--install-directory", "relative"],
    ["--install-directory", ""],
    ["--install-directory", "/bad\0path"],
    ["--install-directory", "/Applications", "--install-directory", "/other"],
    ["--without-profiling", "--without-profiling"],
    ["--unknown"],
  ])
  func rejectsInvalidOptions(flags: [String]) {
    #expect(throws: InstallError.self) {
      try InstallOptions(arguments: ["/package", "Demo"] + flags)
    }
  }
}
