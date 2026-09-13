import Chroma
import RenderFixtures
import Testing

@Test(arguments: RenderFixture.names)
func deterministicReplay(scene: String) throws {
  let fixture = try RenderFixture(name: scene, count: 256)
  #expect(fixture.list.commands == (try RenderFixture(name: scene, count: 256)).list.commands)
  for list in fixture.sequence {
    let frame = FrameObservation(drawList: list, viewport: fixture.viewport)
    let replay = try SceneCapture.decode(SceneCapture.encode(frame))
    #expect(replay.drawList.commands == list.commands)
    #expect(replay.viewport == fixture.viewport)
  }
  let culled = fixture.list.culled(to: fixture.viewport)
  #expect(culled.commands == culled.culled(to: fixture.viewport).commands)
  if scene == "clipped" { #expect(culled.commands.count < fixture.list.commands.count) }
}

@Test(arguments: TranscriptReplay.names)
func transcriptSequencesAreDeterministicAndBounded(scene: String) throws {
  let fixture = try RenderFixture(name: scene, count: 10_000)
  let repeated = try RenderFixture(name: scene, count: 10_000)
  #expect(fixture.sequence.count == 60)
  #expect(fixture.sequence.map(\.commands) == repeated.sequence.map(\.commands))
  #expect(fixture.sequence.allSatisfy { $0.commands.count < 400 })
  #expect(fixture.sequence.first!.commands != fixture.sequence.last!.commands)
  for list in fixture.sequence {
    var depth = 0
    for command in list.commands {
      switch command {
      case .pushClip: depth += 1
      case .popClip: depth -= 1
      default: break
      }
      #expect(depth >= 0)
    }
    #expect(depth == 0)
  }
}
