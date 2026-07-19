import MetalKit

let metalSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct Vertex {
    float2 position;
    float3 color;
  };

  struct VertexOut {
    float4 position [[position]];
    float3 color;
  };

  struct Uniforms {
    float4x4 modelMatrix;
  };

  vertex VertexOut vertex_main(uint vid [[vertex_id]],
                               constant Vertex* vertices [[buffer(0)]],
                               constant Uniforms& uniforms [[buffer(1)]]) {
      VertexOut out;
      out.position = uniforms.modelMatrix * float4(vertices[vid].position, 0.0, 1.0);
      out.color = vertices[vid].color;
      return out;
  }

  fragment float4 fragment_main(VertexOut in [[stage_in]]) {
      return float4(in.color, 1.0);
  }
  """

struct Vertex {
  var positions: SIMD2<Float>
  var color: SIMD3<Float>
}

struct Uniforms {
  var modelMatrix: simd_float4x4
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
  private let pipeline: MTLRenderPipelineState
  private let queue: MTLCommandQueue
  private let vertexBuffer: MTLBuffer
  private let uniformBuffer: MTLBuffer

  var rotation: Float = 0
  var offsetX: Float = 0
  var offsetY: Float = 0

  init?(view: MTKView) {
    guard let device = view.device,
      let queue = device.makeCommandQueue()
    else {
      print("Unable to make command queue.")
      return nil
    }
    self.queue = queue

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard let vertex = library.makeFunction(name: "vertex_main"),
      let fragment = library.makeFunction(name: "fragment_main")
    else {
      print("Function not found in library")
      return nil
    }

    let verties = [
      Vertex(positions: [0.0, 0.8], color: [1, 0, 0]),
      Vertex(positions: [-0.8, -0.8], color: [0, 1, 0]),
      Vertex(positions: [0.8, -0.8], color: [0, 0, 1]),
    ]
    guard
      let vertexBuffer = device.makeBuffer(
        bytes: verties,
        length: MemoryLayout<Vertex>.stride * verties.count,
        options: .storageModeShared)
    else {
      return nil
    }
    self.vertexBuffer = vertexBuffer

    guard
      let uniformBuffer = device.makeBuffer(
        length: MemoryLayout<Uniforms>.stride,
        options: .storageModeShared)
    else {
      return nil
    }
    self.uniformBuffer = uniformBuffer

    let desc = MTLRenderPipelineDescriptor()
    desc.vertexFunction = vertex
    desc.fragmentFunction = fragment
    desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

    do {
      self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
    } catch {
      print("Pipeline creation failed:\n\(error)")
      return nil
    }
  }

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
      let rpd = view.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer(),
      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
    else { return }

    let cosA = cos(rotation)
    let sinA = sin(rotation)
    let rotate = simd_float4x4(rows: [
      [cosA, -sinA, 0, 0],
      [sinA, cosA, 0, 0],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ])
    let translate = simd_float4x4(rows: [
      [1, 0, 0, offsetX],
      [0, 1, 0, offsetY],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ])
    var uniforms = Uniforms(modelMatrix: translate * rotate)
    uniformBuffer.contents().copyMemory(
      from: &uniforms, byteCount: MemoryLayout<Uniforms>.stride)

    enc.setRenderPipelineState(pipeline)
    enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
