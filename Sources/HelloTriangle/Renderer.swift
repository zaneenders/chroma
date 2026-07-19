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

  struct TextInstance {
    float2 dst_p0;   // top-left in NDC
    float2 dst_p1;   // bottom-right in NDC
    float2 tex_tl;   // texture top-left UV
    float2 tex_br;   // texture bottom-right UV
    float4 color;    // rgba
  };

  constant float2 quadPositions[4] = {
    float2(0.0, 0.0),  // top-left
    float2(1.0, 0.0),  // top-right
    float2(0.0, 1.0),  // bottom-left
    float2(1.0, 1.0),  // bottom-right
  };

  struct TextVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
  };

  vertex TextVertexOut text_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   constant TextInstance* instances [[buffer(0)]]) {
      TextVertexOut out;
      TextInstance inst = instances[iid];
      float2 q = quadPositions[vid];
      float2 size = inst.dst_p1 - inst.dst_p0;
      out.position = float4(inst.dst_p0 + q * size, 0.0, 1.0);
      float2 texSize = inst.tex_br - inst.tex_tl;
      out.texCoord = inst.tex_tl + q * texSize;
      out.color = inst.color;
      return out;
  }

  fragment float4 text_fragment(TextVertexOut in [[stage_in]],
                                texture2d<float> fontTex [[texture(0)]]) {
      constexpr sampler s(filter::nearest);
      float a = fontTex.sample(s, in.texCoord).a;
      return float4(in.color.rgb, in.color.a * a);
  }
  """

struct Vertex {
  var positions: SIMD2<Float>
  var color: SIMD3<Float>
}

struct Uniforms {
  var modelMatrix: simd_float4x4
}

struct TextInstance {
  var dst_p0: SIMD2<Float>  // top-left in NDC
  var dst_p1: SIMD2<Float>  // bottom-right in NDC
  var tex_tl: SIMD2<Float>
  var tex_br: SIMD2<Float>
  var color: SIMD4<Float>
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let trianglePipeline: MTLRenderPipelineState
  private let textPipeline: MTLRenderPipelineState
  private let queue: MTLCommandQueue
  private let vertexBuffer: MTLBuffer
  private let uniformBuffer: MTLBuffer
  private let fontAtlas: FontAtlas

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
    self.device = device
    self.queue = queue
    self.fontAtlas = FontAtlas(device: device)

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard let triVert = library.makeFunction(name: "vertex_main"),
      let triFrag = library.makeFunction(name: "fragment_main")
    else {
      print("Triangle functions not found in library")
      return nil
    }

    let triDesc = MTLRenderPipelineDescriptor()
    triDesc.vertexFunction = triVert
    triDesc.fragmentFunction = triFrag
    triDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat

    do {
      self.trianglePipeline = try device.makeRenderPipelineState(descriptor: triDesc)
    } catch {
      print("Triangle pipeline creation failed:\n\(error)")
      return nil
    }

    guard let textVert = library.makeFunction(name: "text_vertex"),
      let textFrag = library.makeFunction(name: "text_fragment")
    else {
      print("Text functions not found in library")
      return nil
    }

    let textDesc = MTLRenderPipelineDescriptor()
    textDesc.vertexFunction = textVert
    textDesc.fragmentFunction = textFrag
    textDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
    // Enable alpha blending for text
    if let ca = textDesc.colorAttachments[0] {
      ca.isBlendingEnabled = true
      ca.sourceRGBBlendFactor = .sourceAlpha
      ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
      ca.rgbBlendOperation = .add
      ca.sourceAlphaBlendFactor = .one
      ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      ca.alphaBlendOperation = .add
    }

    do {
      self.textPipeline = try device.makeRenderPipelineState(descriptor: textDesc)
    } catch {
      print("Text pipeline creation failed:\n\(error)")
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
  }

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
      let rpd = view.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer()
    else { return }

    guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

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

    enc.setRenderPipelineState(trianglePipeline)
    enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

    drawText(enc: enc, viewport: SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height)))

    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }

  private func drawText(enc: MTLRenderCommandEncoder, viewport: SIMD2<Float>) {
    let text = "Hello World!"
    let scale: Float = 2.0  // glyph pixel size multiplier

    // Convert pixel coords to NDC: NDC goes -1..1, so multiply by 2/viewport
    let pxToNDC = Float(2.0) / viewport
    let glyphW = fontAtlas.glyphWidth * scale * pxToNDC.x
    let glyphH = fontAtlas.glyphHeight * scale * pxToNDC.y
    let spacing = fontAtlas.glyphSpacing * scale * pxToNDC.x

    // Position in pixels from top-left, converted to NDC
    let margin: Float = 10.0  // pixels from edge
    let startX: Float = -1.0 + margin * pxToNDC.x
    let startY: Float = 1.0 - margin * pxToNDC.y - glyphH  // top of first glyph

    let chars = Array(text.utf8)
    var instances = [TextInstance]()
    instances.reserveCapacity(chars.count)

    var penX = startX
    for c in chars {
      let (u0, v0, u1, v1) = fontAtlas.glyphUV(c)
      instances.append(
        TextInstance(
          dst_p0: [penX, startY],
          dst_p1: [penX + glyphW, startY + glyphH],
          tex_tl: [u0, v0],
          tex_br: [u1, v1],
          color: [1, 1, 1, 1]
        ))
      penX += glyphW + spacing
    }

    guard !instances.isEmpty,
      let buf = device.makeBuffer(
        bytes: instances,
        length: MemoryLayout<TextInstance>.stride * instances.count,
        options: .storageModeShared)
    else { return }

    enc.setRenderPipelineState(textPipeline)
    enc.setVertexBuffer(buf, offset: 0, index: 0)
    enc.setFragmentTexture(fontAtlas.texture, index: 0)
    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
