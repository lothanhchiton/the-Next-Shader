#ifndef SSPT_GLSL
    #define SSPT_GLSL a

    layout(std430, binding = 1) buffer ssptDenoised0Buffer {
        vec4 ssptDenoised0[];
    };

    int getIndex(ivec2 pixel) {
        pixel = clamp(pixel, ivec2(0), ivec2(viewSize) - 1);
        return pixel.x + pixel.y * int(viewSize.x);
    }

    vec3 cosineHemisphereSample(vec3 N, vec2 rnd) {
        float r = sqrt(rnd.x);
        float theta = 2.0 * PI * rnd.y;

        vec3 up = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 T = normalize(cross(up, N));
        vec3 B = cross(N, T);

        return normalize(T * (r * cos(theta)) + B * (r * sin(theta)) + N * sqrt(max0(1.0 - rnd.x)));
    }

    vec3 mainRender(vec3 viewPos, vec3 worldNormal, vec3 albedo) {
        vec2 rnd = vec2(whiteNoise, RandWellons());
        vec3 rayDirWorld = cosineHemisphereSample(worldNormal, rnd);
        vec3 rayDirView = normalize(mat3(gbufferModelView) * rayDirWorld);

        vec2 hitScreenPos = vec2(0.0);
        bool isHit = false;
        screenRayTracingDDA(viewPos, rayDirView, hitScreenPos, isHit);

        vec3 radiance = vec3(0.0);
        if(isHit) {
            vec2 prevUV = getPreCoord(hitScreenPos);
            radiance = texture(colortex7, outScreen(prevUV) ? hitScreenPos : prevUV).rgb;
        }

        return radiance * albedo;
    }

    vec3 temporalAccumulation(vec3 newSample, vec3 worldPos, ivec2 currentPixel) {
        int currentIdx = getIndex(currentPixel);

        vec3 preScreenPos = getPreScreenPos(worldPos);

        vec3 result = newSample;
        if(inScreen(preScreenPos.xy)) {
            ivec2 prevPixel = ivec2(preScreenPos.xy * vec2(viewSize));

            vec4 history = ssptDenoised0[getIndex(prevPixel)];

            float count = min(history.a + 1.0, SSPT_MAX_FRAMES);
            result = mix(history.rgb, newSample, 1.0 / count);

            ssptData[currentIdx] = vec4(result, count);
        } else {
            ssptData[currentIdx] = vec4(newSample, 1.0);
        }

        return max0(result);
    }

    vec3 sspt(vec3 viewPos, vec3 worldPos, vec3 worldNormal, vec3 albedo) {
        vec3 newSample = mainRender(viewPos, worldNormal, albedo);
        return temporalAccumulation(newSample, worldPos, texelUV) * SSPT_INTENSITY;
    }

#endif