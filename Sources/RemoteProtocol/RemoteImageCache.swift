import Chroma

public struct RemoteImageCache: Sendable {
  private var resources: [ImageID: ImageResource] = [:]
  private var order: [ImageID] = []
  private var bytes = 0
  public private(set) var transmittedPixelBytes = 0
  public init() {}

  func image(id: ImageID) -> ImageResource? { resources[id] }
  mutating func insert(_ image: ImageResource) {
    transmittedPixelBytes += image.rgba8.count
    if let old = resources.removeValue(forKey: image.id) {
      bytes -= old.rgba8.count
      order.removeAll { $0 == image.id }
    }
    resources[image.id] = image
    order.append(image.id)
    bytes += image.rgba8.count
    while order.count > 128 || bytes > 64 * 1024 * 1024 {
      let id = order.removeFirst()
      bytes -= resources.removeValue(forKey: id)!.rgba8.count
    }
  }
}
