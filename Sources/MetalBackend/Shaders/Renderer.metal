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
    constexpr sampler s(min_filter::linear, mag_filter::linear,
                        mip_filter::linear);
    float a = fontTex.sample(s, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * a);
}

struct ShapeInstance {
  float2 dst_p0;
  float2 dst_p1;
  float2 size;
  // top-left, top-right, bottom-right, bottom-left
  float4 radii;
  float4 color;
  float borderWidth;
  float3 padding;
};

struct ShapeVertexOut {
  float4 position [[position]];
  float2 localPosition;
  float2 size;
  float4 radii;
  float4 color;
  float borderWidth;
};

vertex ShapeVertexOut shape_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   constant ShapeInstance* instances [[buffer(0)]]) {
    ShapeInstance inst = instances[iid];
    float2 q = quadPositions[vid];
    ShapeVertexOut out;
    out.position = float4(inst.dst_p0 + q * (inst.dst_p1 - inst.dst_p0), 0.0, 1.0);
    out.localPosition = q * (inst.size + 2.0 * inst.padding.x) - inst.padding.x;
    out.size = inst.size;
    out.radii = inst.radii;
    out.color = inst.color;
    out.borderWidth = inst.borderWidth;
    return out;
}

float roundedRectDistance(float2 localPosition, float2 size, float4 radii) {
    float2 centered = localPosition - size * 0.5;
    float2 q = abs(centered) - size * 0.5;
    float distance = min(max(q.x, q.y), 0.0) + length(max(q, 0.0));

    // A corner can extend past the rectangle's midpoint when the neighboring
    // corner is smaller. Test each corner's actual arc region instead of
    // choosing a radius from the fragment's quadrant.
    float radius = radii.x;
    if (localPosition.x < radius && localPosition.y < radius) {
        distance = max(
            distance,
            length(localPosition - float2(radius, radius)) - radius);
    }

    radius = radii.y;
    if (localPosition.x > size.x - radius && localPosition.y < radius) {
        distance = max(
            distance,
            length(localPosition - float2(size.x - radius, radius)) - radius);
    }

    radius = radii.z;
    if (localPosition.x > size.x - radius && localPosition.y > size.y - radius) {
        distance = max(
            distance,
            length(localPosition - float2(size.x - radius, size.y - radius)) - radius);
    }

    radius = radii.w;
    if (localPosition.x < radius && localPosition.y > size.y - radius) {
        distance = max(
            distance,
            length(localPosition - float2(radius, size.y - radius)) - radius);
    }

    return distance;
}

float shapeCoverage(float distance) {
    float antialiasWidth = max(fwidth(distance), 0.001);
    return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, distance);
}

fragment float4 shape_fragment(ShapeVertexOut in [[stage_in]]) {
    float outerDistance = roundedRectDistance(in.localPosition, in.size, in.radii);
    float alpha = shapeCoverage(outerDistance);

    if (in.borderWidth > 0.0) {
        float2 innerSize = in.size - 2.0 * in.borderWidth;
        if (innerSize.x > 0.0 && innerSize.y > 0.0) {
            float2 innerPosition = in.localPosition - in.borderWidth;
            float4 innerRadii = max(in.radii - in.borderWidth, 0.0);
            float innerDistance = roundedRectDistance(innerPosition, innerSize, innerRadii);
            alpha *= 1.0 - shapeCoverage(innerDistance);
        }
    }

    return float4(in.color.rgb, in.color.a * alpha);
}
