#version 460 core

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// Float uniforms (indices 0..19)
uniform vec2 uSize;                 // 0, 1
uniform vec3 uWhiteBalance;         // 2, 3, 4
uniform float uExposure;            // 5
uniform float uContrast;            // 6
uniform float uBlackLift;           // 7
uniform float uSaturation;          // 8
uniform vec2 uLightDir;             // 9, 10
uniform float uDirectionalStrength; // 11
uniform vec3 uAmbientColor;         // 12, 13, 14
uniform float uAmbientStrength;     // 15
uniform float uLightWrap;           // 16
uniform float uGrain;               // 17
uniform float uBlendStrength;       // 18
uniform float uTimeSeed;            // 19

// Image sampler (index 0)
uniform sampler2D uTexture;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec4 samplePremul(vec2 uv) {
  vec2 clamped = clamp(uv, vec2(0.0), vec2(1.0));
  #ifdef IMPELLER_TARGET_OPENGLES
  clamped.y = 1.0 - clamped.y;
  #endif
  return texture(uTexture, clamped);
}

void main() {
  vec2 safeSize = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / safeSize;

  // Sample all taps in uniform control flow
  vec4 texel = samplePremul(uv);
  vec2 stepPx = vec2(6.0) / max(uSize, vec2(64.0));
  float aR = samplePremul(uv + vec2(stepPx.x, 0.0)).a;
  float aL = samplePremul(uv - vec2(stepPx.x, 0.0)).a;
  float aD = samplePremul(uv + vec2(0.0, stepPx.y)).a;
  float aU = samplePremul(uv - vec2(0.0, stepPx.y)).a;

  float aDR = samplePremul(uv + vec2(stepPx.x, stepPx.y) * 1.4).a;
  float aUL = samplePremul(uv - vec2(stepPx.x, stepPx.y) * 1.4).a;
  float aUR = samplePremul(uv + vec2(stepPx.x, -stepPx.y) * 1.4).a;
  float aDL = samplePremul(uv + vec2(-stepPx.x, stepPx.y) * 1.4).a;

  float alpha = texel.a;
  if (alpha <= 0.002) {
    fragColor = vec4(0.0);
  } else {
    vec3 rawRgb = clamp(texel.rgb / alpha, 0.0, 1.0);
    vec3 col = rawRgb;

    // 1. Exposure + Color Temperature (White Balance)
    float evGain = exp2(uExposure);
    col *= evGain * uWhiteBalance;

    // 2. Pseudo-surface normal & silhouette distance
    vec2 grad = vec2(aL - aR, aU - aD);
    float gradLen = length(grad);
    vec2 rimNormal = gradLen > 0.01 ? (grad / gradLen) : vec2(0.0);
    float avgNeighborAlpha = (aR + aL + aD + aU + aDR + aUL + aUR + aDL) * 0.125;
    float edgeMask = clamp((1.0 - avgNeighborAlpha) * 2.2, 0.0, 1.0);

    // 3. Directional Key / Fill & Rim Lighting
    vec2 bodyPos = (uv - vec2(0.5)) * 2.0;
    float bodyDot = dot(bodyPos, uLightDir);
    float rimDot = dot(rimNormal, uLightDir);

    float keyShade = 1.0 + bodyDot * 0.18 * uDirectionalStrength;
    col *= keyShade;

    float rimLight = max(rimDot, 0.0) * edgeMask * uDirectionalStrength;
    vec3 keyLightTint = mix(vec3(1.0), uWhiteBalance, 0.65);
    col += keyLightTint * rimLight * 0.28;

    float backShade = max(-rimDot, 0.0) * edgeMask * uDirectionalStrength;
    col *= (1.0 - backShade * 0.16);

    // 4. Ground Bounce & Environmental Ambient Tint
    float groundFactor = smoothstep(0.55, 1.0, uv.y);
    vec3 ambientTint = mix(vec3(1.0), uAmbientColor * 1.35 + vec3(0.18), uAmbientStrength);
    col *= mix(vec3(1.0), ambientTint, 0.55);
    col = mix(col, col * 0.65 + uAmbientColor * 0.45, groundFactor * uAmbientStrength * 0.35);

    // 5. Optical Light Wrap
    float wrapAmount = edgeMask * uLightWrap * 0.42;
    vec3 wrapColor = max(uAmbientColor, vec3(0.08)) * 1.15;
    col = mix(col, max(col, wrapColor), wrapAmount);

    // 6. Contrast & Saturation Match
    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(luma), col, uSaturation);
    col = (col - vec3(0.5)) * uContrast + vec3(0.5);

    // 7. Atmospheric Black-Level Lift
    vec3 blackFloor = mix(vec3(0.05), uAmbientColor * 0.45, 0.6) * uBlackLift;
    col = col * (1.0 - uBlackLift * 0.75) + blackFloor;

    // 8. Realistic Smartphone CMOS / Film Grain Injection
    if (uGrain > 0.001) {
      float n = hash12(floor(FlutterFragCoord().xy) + vec2(uTimeSeed * 17.3, uTimeSeed * 31.7)) - 0.5;
      float midWeight = 1.0 - abs(luma - 0.5) * 0.8;
      col += vec3(n * uGrain * 0.28 * midWeight);
    }

    col = clamp(col, 0.0, 1.0);
    vec3 finalRgb = mix(rawRgb, col, clamp(uBlendStrength, 0.0, 1.0));
    fragColor = vec4(finalRgb * alpha, alpha);
  }
}
