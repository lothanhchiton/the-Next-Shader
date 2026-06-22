#ifndef DOF_GLSL
    #define DOF_GLSL a

    vec2 bokehShape(vec2 disk) {
        #if DOF_BOKEH_SHAPE == 0
            return disk;
        #else
            float r = length(disk);
            float theta = atan(disk.y, disk.x);
            float sideAngle = 6.28318530718 / float(DOF_BOKEH_SHAPE);
            float polyR = cos(sideAngle * 0.5) / cos(mod(theta, sideAngle) - sideAngle * 0.5);
            return disk * polyR;
        #endif
    }

    float getCoCPixels(float dist, float focusDist) {
        float f = DOF_FOCAL_LENGTH * 0.001;
        float A = f / max(DOF_FSTOP, 0.1);
        float safeDist = max(dist, 0.05);
        float coc = A * f * (safeDist - focusDist) / (safeDist * max(focusDist - f, 0.001));
        coc *= DOF_COC_SCALE;
        return clamp(coc, -DOF_MAX_COC_PX, DOF_MAX_COC_PX);
    }

    float sampleSceneDist(vec2 uv, out float rawDepth) {
        rawDepth = texture(depthtex0, uv).r;
        if(rawDepth == 1.0) return 1000.0;
        vec3 viewPos = GetViewPosition(uv, rawDepth);
        return length(viewPos);
    }

    vec3 depthOfField(vec2 texcoord) {
        float centerRawDepth;
        float centerDist = sampleSceneDist(texcoord, centerRawDepth);

        #ifdef DOF_BLUR_SKY
            if(centerRawDepth == 1.0) {
                return texelFetch(colortex0, texelUV, 0).rgb;
            }
        #endif

        #if DOF_FOCUS_MODE == 0
            ivec2 centerTexel = ivec2(viewSize * 0.5);
            vec2 centerUV = (vec2(centerTexel) + 0.5) / viewSize;
            float focusRawDepth;
            float focusDist = sampleSceneDist(centerUV, focusRawDepth);
        #else
            float focusDist = DOF_MANUAL_DIST;
        #endif

        float centerCoC = getCoCPixels(centerDist, focusDist);
        float centerRadius = abs(centerCoC);

        if(centerRadius < 0.6) {
            return texelFetch(colortex0, texelUV, 0).rgb;
        }

        vec2 pixelSize = 1.0 / viewSize;
        float dither = interleavedGradientNoise(gl_FragCoord.xy) * 6.28318530718;

        vec3 accumColor = texelFetch(colortex0, texelUV, 0).rgb;
        float accumWeight = 1.0;

        for(int i = 0; i < DOF_SAMPLES; i++) {
            vec2 offset = bokehShape(vogelDiskSample(i, DOF_SAMPLES, dither));

            vec2 sampleUV = texcoord + offset * centerRadius * pixelSize;
            sampleUV = clamp(sampleUV, vec2(0.0), vec2(1.0));

            float sampleRawDepth;
            float sampleDist = sampleSceneDist(sampleUV, sampleRawDepth);
            float sampleCoC = getCoCPixels(sampleDist, focusDist);
            float sampleRadius = abs(sampleCoC);

            float sampleDistPx = length(offset * centerRadius);
            float weight = (sampleCoC >= centerCoC) ? 1.0 : saturate(sampleRadius - sampleDistPx + 1.0);

            vec3 sampleColor = texture(colortex0, sampleUV).rgb;
            accumColor += sampleColor * weight;
            accumWeight += weight;
        }

        return accumColor / max(accumWeight, 1e-4);
    }
#endif