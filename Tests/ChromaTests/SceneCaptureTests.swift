import Chroma
import Foundation
import Testing

@Test func sceneCaptureIsSelfContainedAndPreservesScale() throws {
  var list = DrawList()
  let image = try ImageResource(id: ImageID("capture"), width: 1, height: 1, rgba8: Data([1, 2, 3, 255]))
  list.pushClip(Rect(x: 0, y: 0, width: 40, height: 30))
  list.text("capture", at: .zero, color: .white)
  list.image(image, in: Rect(x: 0, y: 0, width: 10, height: 10))
  list.popClip()
  let frame = FrameObservation(drawList: list, viewport: Size(width: 40, height: 30), rasterScale: Point(x: 2, y: 2))
  let data = try SceneCapture.encode(frame)
  for _ in 0..<2 {
    let decoded = try SceneCapture.decode(data)
    #expect(decoded.drawList.commands == frame.drawList.commands)
    #expect(decoded.viewport == frame.viewport)
    #expect(decoded.rasterScale == frame.rasterScale)
  }
  #expect(throws: (any Error).self) { try SceneCapture.decode(Data(data.dropLast())) }
  #expect(throws: (any Error).self) { try SceneCapture.decode(data + Data([0])) }
  #expect(throws: (any Error).self) { try SceneCapture.decode(Data("not a capture".utf8)) }
}

@Test func captureRejectsInvalidGeometryAndClips() throws {
  for commands: [DrawCommand] in [
    [.popClip], [.pushClip(.zero)],
    [.fillRect(rect: Rect(x: 0, y: 0, width: -1, height: 1), color: .white)],
    [.text(position: .zero, text: "invalid", color: .white, scale: 0)],
  ] {
    let frame = FrameObservation(drawList: DrawList(commands: commands), viewport: Size(width: 40, height: 30))
    #expect(throws: SceneCaptureError.invalidFrame) { try SceneCapture.encode(frame) }
    let data = try JSONEncoder().encode(frame)
    let document = Data("{\"version\":2,\"frame\":".utf8) + data + Data("}".utf8)
    #expect(throws: SceneCaptureError.invalidFrame) { try SceneCapture.decode(document) }
  }
  for frame in [
    FrameObservation(drawList: DrawList(), viewport: .zero),
    FrameObservation(drawList: DrawList(), viewport: Size(width: 1, height: 1), rasterScale: .zero),
  ] {
    #expect(throws: SceneCaptureError.invalidFrame) { try SceneCapture.encode(frame) }
  }
}

@Test func captureRejectsUnknownVersionAndInvalidImageStorage() throws {
  let frame = FrameObservation(drawList: DrawList(), viewport: Size(width: 40, height: 30))
  let data = try SceneCapture.encode(frame)
  var document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  document["version"] = 999
  let unknown = try JSONSerialization.data(withJSONObject: document)
  #expect(throws: SceneCaptureError.unsupportedVersion(999)) { try SceneCapture.decode(unknown) }

  let image = try ImageResource(id: ImageID("test"), width: 1, height: 1, rgba8: Data([0, 0, 0, 255]))
  var storage = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(image)) as? [String: Any])
  storage["width"] = 2
  let malformed = try JSONSerialization.data(withJSONObject: storage)
  #expect(throws: ImageResourceError.invalidByteCount(expected: 8, actual: 4)) {
    try JSONDecoder().decode(ImageResource.self, from: malformed)
  }
}

@Test func capturePreservesEveryDrawingPrimitive() throws {
  let rect = Rect(x: 1, y: 2, width: 20, height: 15)
  let radii = CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
  let commands: [DrawCommand] = [
    .fillRect(rect: rect, color: .white),
    .strokeRect(rect: rect, width: 2, color: .black),
    .fillRoundedRect(rect: rect, radii: radii, color: .white),
    .strokeRoundedRect(rect: rect, radii: radii, width: 1, color: .black),
    .text(position: .zero, text: "café Ångström", color: .white, scale: 0.5),
  ]
  let frame = FrameObservation(drawList: DrawList(commands: commands), viewport: Size(width: 100, height: 50))
  let decoded = try SceneCapture.decode(SceneCapture.encode(frame))
  #expect(decoded.drawList.commands == commands)
  #expect(decoded.rasterScale == nil)
}
