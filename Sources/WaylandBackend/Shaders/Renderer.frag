#version 300 es
precision highp float;
uniform sampler2D uTexture;
in vec2 vUV;
in vec4 vColor;
in vec2 vLocalPosition;
flat in vec2 vSize;
flat in vec4 vRadii;
flat in vec4 vShape;
out vec4 outColor;

float roundedRectDistance(vec2 localPosition, vec2 size, vec4 radii) {
  vec2 centered = localPosition - size * 0.5;
  vec2 q = abs(centered) - size * 0.5;
  float distance = min(max(q.x, q.y), 0.0) + length(max(q, 0.0));

  float radius = radii.x;
  if (localPosition.x < radius && localPosition.y < radius) {
    distance = max(distance, length(localPosition - vec2(radius, radius)) - radius);
  }

  radius = radii.y;
  if (localPosition.x > size.x - radius && localPosition.y < radius) {
    distance = max(distance, length(localPosition - vec2(size.x - radius, radius)) - radius);
  }

  radius = radii.z;
  if (localPosition.x > size.x - radius && localPosition.y > size.y - radius) {
    distance = max(
      distance, length(localPosition - vec2(size.x - radius, size.y - radius)) - radius);
  }

  radius = radii.w;
  if (localPosition.x < radius && localPosition.y > size.y - radius) {
    distance = max(distance, length(localPosition - vec2(radius, size.y - radius)) - radius);
  }

  return distance;
}

float shapeCoverage(float distance) {
  float antialiasWidth = max(fwidth(distance), 0.001);
  return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, distance);
}

void main() {
  float coverage;
  if (vShape.w > 0.5) {
    outColor = texture(uTexture, vUV) * vColor;
    return;
  } else if (vShape.z > 0.5) {
    float outerDistance = roundedRectDistance(vLocalPosition, vSize, vRadii);
    coverage = shapeCoverage(outerDistance);
    float borderWidth = vShape.x;
    if (borderWidth > 0.0) {
      vec2 innerSize = vSize - 2.0 * borderWidth;
      if (innerSize.x > 0.0 && innerSize.y > 0.0) {
        vec2 innerPosition = vLocalPosition - borderWidth;
        vec4 innerRadii = max(vRadii - borderWidth, 0.0);
        float innerDistance = roundedRectDistance(innerPosition, innerSize, innerRadii);
        coverage *= 1.0 - shapeCoverage(innerDistance);
      }
    }
  } else {
    coverage = texture(uTexture, vUV).r;
  }
  outColor = vec4(vColor.rgb, vColor.a * coverage);
}
