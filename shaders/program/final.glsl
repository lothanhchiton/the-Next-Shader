#include "/lib/basefiles.glsl"

varying vec2 texcoord;

#ifdef VSH

    void main() {
        gl_Position = ftransform();
        texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    }

#endif

#ifdef FSH

    #include "/lib/final.glsl"
    #include "/lib/exposure.glsl"

    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 color0;

    void main() {
        vec3 outcol = texture(colortex0, texcoord).rgb;

        float avgLuminance = texelFetch(colortex7, ivec2(0, 0), 0).a;
        outcol = avgExposure(outcol, avgLuminance);

        float depth = texture(depthtex1, texcoord).r;
        if(depth < 1.0) {
            float uv1x = texelFetch(colortex1, texelUV, 0).r;
            if(heldBlockLightValue > 0.0) {
                vec3 viewPos = GetViewPosition(texcoord, depth);
                float disToLight = distance(viewPos, handPosition);
                uv1x += saturate(1.0 - disToLight / 8.0);
            }
            if(heldBlockLightValue2 > 0.0) {
                vec3 viewPos = GetViewPosition(texcoord, depth);
                float disToLight = distance(viewPos, handPosition2);
                uv1x += saturate(1.0 - disToLight / 8.0);
            }
            uv1x = saturate(uv1x);
            float factor = remapSaturate(avgLuminance / (avgLuminance + 1.0), 0.0, 0.01, 0.5, 1.0);
            factor = mix(factor, 1.0, uv1x);
            outcol = saturation(outcol, factor);
            outcol.r *= factor * 0.8 + 0.2;
            outcol.g *= factor * 0.6 + 0.4;
        }

        float halo = pow2(1.0 - length(texcoord * 2.0 - 1.0) / sqrt(2.0)) * 0.5 + 0.5;
        outcol *= halo;

        outcol = agx(outcol);
        outcol = LinearToGamma(outcol);

        color0 = vec4(outcol, 1.0);
    }

#endif
