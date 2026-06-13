

#include "/lib/basefiles.glsl"

const vec2 workGroupsRender = vec2(1.0, 1.0);

layout (local_size_x = 16, local_size_y = 16) in;

layout(std430, binding = 0) buffer ssptBuffer {
    vec4 ssptData[];
};

layout(std430, binding = 1) buffer ssptDenoised0Buffer {
    vec4 ssptDenoised0[];
};

const float kernel[3] = float[3](1.0, 2.0/3.0, 1.0/6.0);

int getIndex(ivec2 pixel) {
    pixel = clamp(pixel, ivec2(0), ivec2(viewSize) - 1);
    return pixel.x + pixel.y * int(viewSize.x);
}

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if(px.x >= int(viewSize.x) || px.y >= int(viewSize.y)) return;

    int centerIdx = getIndex(px);
    vec4 centerData = ssptData[centerIdx];

    float centerDepth = texelFetch(depthtex1, px, 0).r;
    if(centerDepth >= 1.0) {
        ssptDenoised0[centerIdx] = centerData;
        return;
    }

    vec4 d2 = texelFetch(colortex2, px, 0);
    vec3 centerNormal = normalDecode(d2.zw);
    float centerLuma = luma(centerData.rgb);

    float meanLuma = 0.0;
    float meanLuma2 = 0.0;
    float wsum0 = 0.0;
    for(int j = -1; j <= 1; j++) {
        for(int i = -1; i <= 1; i++) {
            ivec2 p = px + ivec2(i, j);
            if(p.x < 0 || p.y < 0 || p.x >= int(viewSize.x) || p.y >= int(viewSize.y)) continue;
            float l = luma(ssptData[getIndex(p)].rgb);
            meanLuma += l;
            meanLuma2 += l * l;
            wsum0 += 1.0;
        }
    }
    meanLuma /= wsum0;
    meanLuma2 /= wsum0;
    float variance = max(meanLuma2 - meanLuma * meanLuma, 1e-6);

    float histFactor = clamp(1.0 - centerData.a / SSPT_MAX_FRAMES, 0.1, 1.0);

    vec3 sumColor = centerData.rgb * kernel[0] * kernel[0];
    float sumWeight = kernel[0] * kernel[0];

    for(int j = -2; j <= 2; j++) {
        for(int i = -2; i <= 2; i++) {
            if(i == 0 && j == 0) continue;

            ivec2 p = px + ivec2(i, j) * 1;
            if(p.x < 0 || p.y < 0 || p.x >= int(viewSize.x) || p.y >= int(viewSize.y)) continue;

            float sampleDepth = texelFetch(depthtex1, p, 0).r;
            if(sampleDepth >= 1.0) continue;

            vec4 d2s = texelFetch(colortex2, p, 0);
            vec3 sampleNormal = normalDecode(d2s.zw);

            vec4 sampleData = ssptData[getIndex(p)];
            float sampleLuma = luma(sampleData.rgb);

            float kw = kernel[abs(i)] * kernel[abs(j)];

            float depthDiff = abs(centerDepth - sampleDepth);
            float wDepth = exp(-depthDiff / (0.25 * 0.01 + 1e-6));

            float normalDot = max(dot(centerNormal, sampleNormal), 0.0);
            float wNormal = pow(normalDot, 32.0);

            float lumaDiff = abs(centerLuma - sampleLuma);
            float wLuma = exp(-lumaDiff * lumaDiff / (4.0 * sqrt(variance) * histFactor + 1e-6));

            float w = kw * wDepth * wNormal * wLuma;

            sumColor += sampleData.rgb * w;
            sumWeight += w;
        }
    }

    vec3 filtered = sumColor / max(sumWeight, 1e-6);
    ssptDenoised0[centerIdx] = vec4(filtered, centerData.a);
}