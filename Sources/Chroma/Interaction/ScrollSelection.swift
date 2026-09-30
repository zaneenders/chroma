import Observation

@Observable
@MainActor
public final class ScrollSelection<ID: Hashable & Sendable> {
  public enum MissingPolicy {
    case clear
    case first
    case last
  }

  public var selectedID: ID?

  public init(_ selectedID: ID? = nil) { self.selectedID = selectedID }

  @discardableResult
  public func move(in ids: [ID], by distance: Int, ifMissing policy: MissingPolicy = .clear) -> ID? {
    guard !ids.isEmpty else {
      selectedID = nil
      return nil
    }
    guard let selectedID, let index = ids.firstIndex(of: selectedID) else {
      switch policy {
      case .clear: self.selectedID = nil
      case .first: self.selectedID = ids.first
      case .last: self.selectedID = ids.last
      }
      return self.selectedID
    }
    self.selectedID = ids[max(0, min(ids.count - 1, index + distance))]
    return self.selectedID
  }
}
