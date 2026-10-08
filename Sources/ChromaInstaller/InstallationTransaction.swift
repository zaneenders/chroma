import Foundation

struct RollbackFailure: Error, CustomStringConvertible {
  let description: String
}

/// Stage on the destination filesystem. Restore every replaced file if any move fails.
/// The injectable move operation lets tests exercise failures without filesystem races.
func replaceInstalledFiles(
  _ replacements: [(source: URL, destination: URL)], staging: URL,
  move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
) throws {
  let fm = FileManager.default
  var backups: [(URL, URL)] = []
  var installed: [URL] = []
  do {
    for (source, destination) in replacements {
      try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      if exists(destination) {
        let backup = staging.appendingPathComponent("backup-\(backups.count)")
        try move(destination, backup)
        backups.append((backup, destination))
      }
      try move(source, destination)
      installed.append(destination)
    }
  } catch {
    let original = error
    do {
      for destination in installed.reversed() { try fm.removeItem(at: destination) }
      for (backup, destination) in backups.reversed() { try move(backup, destination) }
    } catch {
      throw RollbackFailure(
        description: "Installation failed: \(original). Rollback failed: \(error). Backups preserved at \(staging.path)"
      )
    }
    throw original
  }
}
