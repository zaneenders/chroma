#if WAYLAND_BACKEND

let vertexShader = """
#version 300 es
layout(location=0) in vec2 aQuad;
layout(location=1) in vec2 iDst0;
layout(location=2) in vec2 iDst1;
layout(location=3) in vec2 iUV0;
layout(location=4) in vec2 iUV1;
layout(location=5) in vec4 iColor;
layout(location=6) in vec2 iSize;
layout(location=7) in vec4 iRadii;
layout(location=8) in vec4 iShape;
uniform vec2 uResolution;
out vec2 vUV;
out vec4 vColor;
out vec2 vLocalPosition;
flat out vec2 vSize;
flat out vec4 vRadii;
flat out vec4 vShape;
void main() {
  vec2 t = 0.5 * (aQuad + 1.0);
  vec2 pixel = mix(iDst0, iDst1, t);
  gl_Position = vec4(pixel.x / uResolution.x * 2.0 - 1.0,
                     1.0 - pixel.y / uResolution.y * 2.0, 0.0, 1.0);
  vUV = mix(iUV0, iUV1, t);
  vColor = iColor;
  vLocalPosition = t * (iSize + 2.0 * iShape.y) - iShape.y;
  vSize = iSize;
  vRadii = iRadii;
  vShape = iShape;
}
"""

let fragmentShader = """
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
  if (vShape.z > 0.5) {
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
"""

#endif
