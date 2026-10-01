@MainActor
public enum EngineDiagnostics {
  public static var enabled = false
  public static var bodyEvaluations = 0
  public static var registrationPasses = 0
  public static var primitivePaintVisits = 0
  public static var visibleLazyRowVisits = 0
  public static var focusArrayCapacityGrowth = 0

  public static func reset() {
    bodyEvaluations = 0
    registrationPasses = 0
    primitivePaintVisits = 0
    visibleLazyRowVisits = 0
    focusArrayCapacityGrowth = 0
  }
}
