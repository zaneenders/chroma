#if WAYLAND_BACKEND

let vertexShader = """
#version 300 es
layout(location=0) in vec2 aQuad;
layout(location=1) in vec2 iDst0;
layout(location=2) in vec2 iDst1;
layout(location=3) in vec2 iUV0;
layout(location=4) in vec2 iUV1;
layout(location=5) in vec4 iColor;
uniform vec2 uResolution;
out vec2 vUV;
out vec4 vColor;
void main() {
  vec2 t = 0.5 * (aQuad + 1.0);
  vec2 pixel = mix(iDst0, iDst1, t);
  gl_Position = vec4(pixel.x / uResolution.x * 2.0 - 1.0,
                     1.0 - pixel.y / uResolution.y * 2.0, 0.0, 1.0);
  vUV = mix(iUV0, iUV1, t);
  vColor = iColor;
}
"""

let fragmentShader = """
#version 300 es
precision mediump float;
uniform sampler2D uTexture;
in vec2 vUV;
in vec4 vColor;
out vec4 outColor;
void main() {
  float coverage = texture(uTexture, vUV).r;
  outColor = vec4(vColor.rgb, vColor.a * coverage);
}
"""

#endif
