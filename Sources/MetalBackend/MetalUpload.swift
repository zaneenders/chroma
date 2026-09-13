#if METAL_BACKEND

import Metal

/// The CPU-to-Metal memory boundary. Calls copy synchronously from borrowed
/// storage. Pooled destinations are private to the renderer and protected by
/// its prepared-frame reservation until submission completes.
@MainActor
enum MetalUpload {
  static func copy<Element: BitwiseCopyable>(_ values: [Element], to buffer: MTLBuffer) {
    guard !values.isEmpty else { return }
    values.withUnsafeBytes { bytes in
      precondition(bytes.count <= buffer.length)
      precondition(buffer.storageMode == .shared)
      // Metal owns raw storage, not initialized Swift Elements. Copy bytes rather
      // than assuming an existing typed binding and updating uninitialized values.
      unsafe buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }
  }

  static func setVertexValue<Value: BitwiseCopyable>(
    _ value: inout Value, encoder: MTLRenderCommandEncoder, index: Int
  ) {
    withUnsafeBytes(of: &value) { bytes in
      precondition(bytes.count <= 4096)
      // setVertexBytes copies the value before this closure returns. Use the
      // actual accessible byte count, not stride (which can include tail padding).
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
      // The validated full mip has tightly packed rows. replace copies these
      // bytes synchronously; Metal does not retain the borrowed CPU pointer.
      unsafe texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level,
        withBytes: buffer.baseAddress!, bytesPerRow: rowBytes)
    }
  }
}

#endif
