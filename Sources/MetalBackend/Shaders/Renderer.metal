#include <metal_stdlib>
using namespace metal;
struct ShapeInstance {
  float2 dst_p0;
  float2 dst_p1;
  float2 size;
  float4 radii;
  float4 topLeft;
  float4 topRight;
  float4 bottomRight;
  float4 bottomLeft;
  float2 uv0;
  float2 uv1;
  float4 parameters;
};
struct ShapeVertexOut {
  float4 position [[position]];
  float2 localPosition;
  float2 uv;
  float2 size;
  float4 radii;
  float4 color;
  float4 parameters;
};
constant float2 corners[4] = {float2(0,0), float2(1,0), float2(0,1), float2(1,1)};
vertex ShapeVertexOut shape_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                  constant ShapeInstance* instances [[buffer(0)]]) {
  ShapeInstance inst = instances[iid];
  float2 q = corners[vid];
  ShapeVertexOut out;
  out.position = float4(mix(inst.dst_p0, inst.dst_p1, q), 0, 1);
  out.localPosition = q * (inst.size + 2 * inst.parameters.z) - inst.parameters.z;
  float2 t = out.localPosition / inst.size;
  out.uv = mix(inst.uv0, inst.uv1, t);
  out.color = mix(mix(inst.topLeft, inst.topRight, t.x),
                  mix(inst.bottomLeft, inst.bottomRight, t.x), t.y);
  out.size = inst.size;
  out.radii = inst.radii;
  out.parameters = inst.parameters;
  return out;
}
float roundedRectDistance(float2 localPosition, float2 size, float4 radii) {
    float2 centered = localPosition - size * 0.5;
    float2 q = abs(centered) - size * 0.5;
    float distance = min(max(q.x, q.y), 0.0) + length(max(q, 0.0));

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


float coverage(float distance, float softness) {
  float width = max(max(fwidth(distance), softness), 0.001);
  return 1 - smoothstep(-width, width, distance);
}
fragment float4 shape_fragment(ShapeVertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]]) {
  constexpr sampler s(min_filter::linear, mag_filter::linear,
                      mip_filter::linear, address::clamp_to_edge);
  float4 sample = texture.sample(s, in.uv);
  if (in.parameters.w > 0.5) sample = float4(1, 1, 1, sample.r);
  float alpha = coverage(roundedRectDistance(in.localPosition, in.size, in.radii), in.parameters.y);
  float border = in.parameters.x;
  float2 innerSize = in.size - 2 * border;
  if (border > 0 && innerSize.x > 0 && innerSize.y > 0) {
    alpha *= 1 - coverage(roundedRectDistance(in.localPosition - border, innerSize,
                                             max(in.radii - border, 0.0)), in.parameters.y);
  }
  float4 result = sample * in.color;
  result.a *= alpha;
  return result;
}
