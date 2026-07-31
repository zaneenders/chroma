#include <metal_stdlib>
using namespace metal;

struct TextInstance {
  float2 dst_p0;
  float2 dst_p1;
  float2 tex_tl;
  float2 tex_br;
  float4 color;
};

constant float2 quadPositions[4] = {
  float2(0.0, 0.0),
  float2(1.0, 0.0),
  float2(0.0, 1.0),
  float2(1.0, 1.0),
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
    float a = fontTex.sample(s, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * a);
}

struct GUIVertex {
  float2 position;
  float2 uv;
  float4 color;
};

struct SolidVertexOut {
  float4 position [[position]];
  float4 color;
};

vertex SolidVertexOut solid_vertex(uint vid [[vertex_id]],
                                   constant GUIVertex* vertices [[buffer(0)]]) {
    SolidVertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.color = vertices[vid].color;
    return out;
}

fragment float4 solid_fragment(SolidVertexOut in [[stage_in]]) {
    return in.color;
}
