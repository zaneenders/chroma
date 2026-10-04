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
  float antialiasWidth = max(max(fwidth(distance), vShape.z), 0.001);
  return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, distance);
}

void main() {
  vec4 sampleColor = texture(uTexture, vUV);
  if (vShape.w > 0.5) sampleColor = vec4(1.0, 1.0, 1.0, sampleColor.r);
  float coverage = shapeCoverage(roundedRectDistance(vLocalPosition, vSize, vRadii));
  float border = vShape.x;
  vec2 innerSize = vSize - 2.0 * border;
  if (border > 0.0 && innerSize.x > 0.0 && innerSize.y > 0.0) {
    coverage *= 1.0 - shapeCoverage(roundedRectDistance(
      vLocalPosition - border, innerSize, max(vRadii - border, 0.0)));
  }
  outColor = sampleColor * vColor;
  outColor.a *= coverage;
}
