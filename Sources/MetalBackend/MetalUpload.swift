import Metal

@MainActor
enum MetalUpload {
  static func copy<Element: BitwiseCopyable>(_ values: [Element], to buffer: MTLBuffer) {
    guard !values.isEmpty else { return }
    values.withUnsafeBytes { bytes in
      precondition(bytes.count <= buffer.length)
      precondition(buffer.storageMode == .shared)
      unsafe buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }
  }

  static func setVertexValue<Value: BitwiseCopyable>(
    _ value: inout Value, encoder: MTLRenderCommandEncoder, index: Int
  ) {
    withUnsafeBytes(of: &value) { bytes in
      precondition(bytes.count <= 4096)
      unsafe encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: index)
    }
  }

  static func replace(
    _ texture: MTLTexture, bytes: RawSpan, width: Int, height: Int,
    bytesPerPixel: Int, level: Int
  ) {
    precondition(width > 0 && height > 0 && level >= 0 && level < texture.mipmapLevelCount)
    precondition(width == max(1, texture.width >> level))
    precondition(height == max(1, texture.height >> level))
    precondition(
      (texture.pixelFormat == .r8Unorm && bytesPerPixel == 1)
        || (texture.pixelFormat == .rgba8Unorm && bytesPerPixel == 4))
    let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
    let (totalBytes, totalOverflow) = rowBytes.multipliedReportingOverflow(by: height)
    precondition(!rowOverflow && !totalOverflow && totalBytes == bytes.byteCount)
    bytes.withUnsafeBytes { buffer in
      unsafe texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level,
        withBytes: buffer.baseAddress!, bytesPerRow: rowBytes)
    }
  }
}
