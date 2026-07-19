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
