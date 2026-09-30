public enum BackendError: Error, Equatable, Sendable {
  case unavailable(backend: String, reason: String)
  case initializationFailed(backend: String, stage: String, reason: String)
  case notImplemented(backend: String)
}

extension BackendError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unavailable(let backend, let reason):
      return "\(backend) backend is unavailable: \(reason)"
    case .initializationFailed(let backend, let stage, let reason):
      return "\(backend) backend failed to initialize \(stage): \(reason)"
    case .notImplemented(let backend):
      return "\(backend) backend is not implemented"
    }
  }
}
