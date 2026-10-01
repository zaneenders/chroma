import Chroma
import ChromaTesting
import Testing

@MainActor
struct EngineDiagnosticsTests {
  @Test func diagnosticsAreOptIn() {
    defer {
      EngineDiagnostics.enabled = false
      EngineDiagnostics.reset()
    }
    let host = HeadlessHost()
    host.content = Text("diagnostics")
    EngineDiagnostics.enabled = false
    EngineDiagnostics.reset()
    host.renderScheduled()
    #expect(EngineDiagnostics.registrationPasses == 0)
    #expect(EngineDiagnostics.primitivePaintVisits == 0)
    EngineDiagnostics.enabled = true
    host.render()
    #expect(EngineDiagnostics.registrationPasses > 0)
    #expect(EngineDiagnostics.primitivePaintVisits > 0)
    host.close()
  }
}
