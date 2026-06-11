

#include "/lib/basefiles.glsl"

varying vec2 texcoord;

#ifdef VSH

    void main() {
        gl_Position = ftransform();
        texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    }

#endif

#ifdef FSH

    #include "/lib/light.glsl"
    #include "/lib/sky.glsl"
    #include "/lib/cloud.glsl"

    /* RENDERTARGETS: 4,5,6 */
    layout(location = 0) out vec4 color4;
    layout(location = 1) out vec4 color5;
    layout(location = 2) out vec4 color6;

    const float GW5[5] = float[5](0.0625, 0.25, 0.375, 0.25, 0.0625);

    vec4 bilateralH(vec2 tc, vec2 tc4) {
        ivec2 cUV4 = ivec2(tc4 * viewSize);
        float cDepth = texelFetch(depthtex1, cUV4, 0).r;
        vec4 center = texelFetch(colortex4, ivec2(tc * viewSize), 0);

        if (cDepth >= 1.0) return center;

        vec3 cN = normalDecode(texelFetch(colortex2, cUV4, 0).xy);
        float cLinZ = linearDepth(cDepth);

        vec4 acc = vec4(0.0);
        float wAcc = 0.0;

        for (int i = -2; i <= 2; i++) {
            vec2 sTC = tc + vec2(float(i), 0.0) / viewSize;
            vec2 sTC4 = sTC * 2.0;
            if (!inScreen(sTC4)) continue;

            ivec2 sUV4 = ivec2(sTC4 * viewSize);
            float sDepth = texelFetch(depthtex1, sUV4, 0).r;
            if (sDepth >= 1.0) continue;

            vec3 sN = normalDecode(texelFetch(colortex2, sUV4, 0).xy);
            float sLinZ = linearDepth(sDepth);

            float wG = GW5[i + 2];
            float wN = pow(max(0.0, dot(cN, sN)), 32.0);
            float wD = exp(-abs(cLinZ - sLinZ) * 3.0);
            float w = wG * wN * wD;

            acc += texelFetch(colortex4, ivec2(sTC * viewSize), 0) * w;
            wAcc += w;
        }

        return (wAcc > 1e-6) ? acc / wAcc : center;
    }

    void main() {
        vec4 outcol4 = texelFetch(colortex4, texelUV, 0);
        vec3 outcol5 = texelFetch(colortex5, texelUV, 0).rgb;
        vec4 outcol6 = texelFetch(colortex6, texelUV, 0);

        vec2 texcoord4 = texcoord * 2.0;
        if (inScreen(texcoord4)) {
            float depth = texelFetch(depthtex1, ivec2(texcoord4 * viewSize), 0).r;
            if (depth < 1.0) {
                outcol6 = bilateralH(texcoord, texcoord4);
            }
        }

        vec2 texcoord5 = texcoord * 4.0;
        if (inScreen(texcoord5)) {
            outcol5 = RenderSky(tex2sph(texcoord5));
        }

        if (texelUV == ivec2(viewSize - 1.0) - ivec2(0, 0))
            outcol5 = sunLuminance * TransToAtmos(cameraLocation, sunDir);
        if (texelUV == ivec2(viewSize - 1.0) - ivec2(1, 0))
            outcol5 = moonLuminance * TransToAtmos(cameraLocation, moonDir);

        color4 = outcol4;
        color5 = vec4(outcol5, 1.0);
        color6 = outcol6;
    }

#endif