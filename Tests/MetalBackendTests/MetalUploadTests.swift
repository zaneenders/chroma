import Metal
import Testing

@testable import MetalBackend

@Suite @MainActor
struct MetalUploadTests {
  @Test func copiesInstancesWithoutOverwritingBufferTail() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let values: [UInt32] = [0x0102_0304, 0xAABB_CCDD]
    let buffer = try #require(device.makeBuffer(length: 16, options: .storageModeShared))
    unsafe buffer.contents().initializeMemory(as: UInt8.self, repeating: 0xEE, count: 16)
    MetalUpload.copy(values.span, to: buffer)
    let bytes = unsafe UnsafeRawBufferPointer(start: buffer.contents(), count: buffer.length)
    #expect(unsafe bytes.loadUnaligned(fromByteOffset: 0, as: UInt32.self) == values[0])
    #expect(unsafe bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self) == values[1])
    #expect(unsafe Array(bytes[8..<16]) == Array(repeating: UInt8(0xEE), count: 8))
    MetalUpload.copy([UInt32]().span, to: buffer)
    #expect(unsafe bytes.loadUnaligned(fromByteOffset: 0, as: UInt32.self) == values[0])
  }

  @Test func uploadsOddWidthMipAndRGBABytes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for (format, components): (MTLPixelFormat, Int) in [(.r8Unorm, 1), (.rgba8Unorm, 4)] {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: 3, height: 2, mipmapped: true)
      descriptor.storageMode = .shared
      let texture = try #require(device.makeTexture(descriptor: descriptor))
      for level in 0..<texture.mipmapLevelCount {
        let width = max(1, 3 >> level)
        let height = max(1, 2 >> level)
        let pixels = (0..<(width * height * components)).map { UInt8($0 + level) }
        MetalUpload.replace(
          texture, bytes: pixels.span.bytes, width: width, height: height,
          bytesPerPixel: components, level: level)
        var result = [UInt8](repeating: 0xFF, count: pixels.count)
        result.withUnsafeMutableBytes { bytes in
          unsafe texture.getBytes(
            bytes.baseAddress!, bytesPerRow: width * components,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level)
        }
        #expect(result == pixels)
      }
    }
  }

  @Test func instanceLayoutsMatchMetalShaders() {
    #expect(MemoryLayout<TextInstance>.size == 48)
    #expect(MemoryLayout<TextInstance>.stride == 48)
    #expect(MemoryLayout<ShapeInstance>.stride == 96)
    #expect(MemoryLayout<ShapeInstance>.offset(of: \.radii) == 32)
    #expect(MemoryLayout<ShapeInstance>.offset(of: \.color) == 48)
    #expect(MemoryLayout<ShapeInstance>.offset(of: \.borderWidth) == 64)
  }
}
