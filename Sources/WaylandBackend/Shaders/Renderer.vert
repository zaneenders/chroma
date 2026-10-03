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
layout(location=9) in vec4 iTopRight;
layout(location=10) in vec4 iBottomRight;
layout(location=11) in vec4 iBottomLeft;
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
  vec2 local = t * (iSize + 2.0 * iShape.y) - iShape.y;
  vec2 uv = local / iSize;
  vUV = mix(iUV0, iUV1, uv);
  vColor = mix(mix(iColor, iTopRight, uv.x), mix(iBottomLeft, iBottomRight, uv.x), uv.y);
  vLocalPosition = t * (iSize + 2.0 * iShape.y) - iShape.y;
  vSize = iSize;
  vRadii = iRadii;
  vShape = iShape;
}
