#ifndef LIGHT_GLSL
    #define LIGHT_GLSL a

    vec3 CalculateDirectlight(vec3 albedo, float roughness, float metallic, vec3 worldNormal, vec3 worldDir, vec3 sunlight, vec3 moonlight) {
        vec3 sun_directlight = vec3(0.0);
        if(rayIntersectSphere(vec3(0.0, AtmosphereRadius, 0.0), sunDir, EarthRadiusSquared) <= 0.0) {
            vec3 sun_brdf  = Cook_Torrance_BRDF(albedo, roughness, metallic, worldNormal, -worldDir, sunDir);
            float sun_NdotL  = max(dot(worldNormal, sunDir), 0.0);

            sun_directlight = sun_brdf * sun_NdotL * sunlight;
        }

        vec3 moon_directlight = vec3(0.0);
        if(rayIntersectSphere(vec3(0.0, AtmosphereRadius, 0.0), moonDir, EarthRadiusSquared) <= 0.0) {
            vec3 moon_brdf = Cook_Torrance_BRDF(albedo, roughness, metallic, worldNormal, -worldDir, moonDir);
            float moon_NdotL = max(dot(worldNormal, moonDir), 0.0);

            moon_directlight = moon_brdf * moon_NdotL * moonlight;

        }

        return sun_directlight + moon_directlight;
    }

    vec3 RSM(vec3 worldPos_p, vec3 worldNormal_p) {
        int sampleCount = int(remapSaturate(length(worldPos_p), 0.0, shadowDistance, 12.0, 6.0));
        float f_sample = float(sampleCount);
        float radius = 100.0 / float(shadowMapResolution);

        float jitter = whiteNoise;

        float angle = blueNoise * _2PI;
        vec2 dir = vec2(cos(angle), sin(angle));

        vec3 shadowPos_p = WorldSpaceToShadowSpaceNoDistort(worldPos_p);

        vec3 rsm = vec3(0.0);
        float c = 0.0;
        for(int i = 0; i < sampleCount; i++) {
            float fi = float(i);
            float u = (fi + jitter) / f_sample;
            float r = radius * u;
            vec2 offst = dir * r;

            dir = goldenRot * dir;

            vec2 coord = shadowPos_p.xy + offst;
            coord = shadowDistort(vec3(coord, shadowPos_p.z) * 2.0 - 1.0).xy * 0.5 + 0.5;

            if(outScreen(coord)) continue;

            vec3 shadowPos_q = vec3(coord, textureLod(shadowtex1, coord, 0).r);
            if(shadowPos_q.z >= 1.0) continue;
            vec3 worldPos_q = ShadowSpaceToWorldSpace(shadowPos_q);
            vec3 worldNormal_q = normalize(textureLod(shadowcolor1, coord, 0).rgb * 2.0 - 1.0);

            vec3  worldDir_pq = normalize(worldPos_q - worldPos_p);
            float worldDis_pq = distance(worldPos_q, worldPos_p);

            vec4 shadowcolor = textureLod(shadowcolor0, coord, 0);
            vec3 flux_q = shadowcolor.rgb * shadowcolor.a;

            float costheta_p = max0(dot(worldNormal_p,  worldDir_pq));
            float costheta_q = max0(dot(worldNormal_q, -worldDir_pq));
            float NdotL = max0(dot(worldNormal_q, lightDir));

            float sampleWeight = 2.0 * u;
            rsm += flux_q * NdotL * costheta_p * costheta_q / max(pow2(worldDis_pq), 0.5) * saturate(exp2(-worldDis_pq * 0.1)) * sampleWeight;
            c ++;
        }
        if(c < 0.5) return vec3(0.0);

        return rsm / c * 500.0 * remapSaturate(length(worldPos_p), 0.0, shadowDistance, 1.0, 0.0);
    }

    vec4 rsmBlur(sampler2D tex, vec2 uv, vec2 dir) {
        float depth = texture(depthtex1, uv * 2.0).r;
        vec3 worldNormal = normalDecode(texture(colortex2, uv * 2.0).rg);

        float weight[3] = float[](0.4026, 0.2442, 0.0545);

        vec2 dx = invViewSize * dir;
        float viewz = linearDepth(depth);
        dx *= mix(1.0, 0.1, viewz / far) * 0.5;

        vec4 col = texture(tex, uv) * weight[0];
        float c = weight[0];
        for(int i = 1; i <= 2; i++) {
            float fi = float(i);
            float w1 = weight[i];
            float w2 = w1;

            vec2 uv1 = uv + dx * fi;
            float depth1 = texture(depthtex1, uv1 * 2.0).r;
            vec3 worldNormal1 = normalDecode(texture(colortex2, uv1 * 2.0).rg);

            float viewz1 = linearDepth(depth1);
            float depthDiff1 = abs(viewz1 - viewz) / max(viewz, 1e-3);
            float depthOk1 = 1.0 - smoothstep(0.01, 0.05, depthDiff1);
            float normalOk1 = smoothstep(0.5, 0.9, dot(worldNormal1, worldNormal));

            w1 *= depthOk1 * normalOk1;
            col += texture(tex, uv1) * w1;
            c += w1;

            vec2 uv2 = uv - dx * fi;
            float depth2 = texture(depthtex1, uv2 * 2.0).r;
            vec3 worldNormal2 = normalDecode(texture(colortex2, uv2 * 2.0).rg);

            float viewz2 = linearDepth(depth2);
            float depthDiff2 = abs(viewz2 - viewz) / max(viewz, 1e-3);
            float depthOk2 = 1.0 - smoothstep(0.01, 0.05, depthDiff2);
            float normalOk2 = smoothstep(0.5, 0.9, dot(worldNormal2, worldNormal));

            w2 *= depthOk2 * normalOk2;
            col += texture(tex, uv2) * w2;
            c += w2;
        }

        return col / c;
    }

    vec3 SSS(vec3 color, vec3 worldPos, vec3 worldDir, vec3 lightcol) {
        vec3 distortShadowPos = WorldSpaceToShadowSpace(worldPos);

        const int sampleCount = 4;
        float radius = 2.0 / float(shadowMapResolution);

        vec3 shadowPos = shadowUnDistort(distortShadowPos * 2.0 - 1.0) * 0.5 + 0.5;

        float jitter = whiteNoise;

        float angle = blueNoise * _2PI;
        vec2  dir = vec2(cos(angle), sin(angle));

        vec3 centerShadowPos = distortShadowPos;
        float centerDepth = textureLod(shadowtex1, centerShadowPos.xy, 0).r;

        float sssdepth = 0.0;
        int c = 0;
        if(centerShadowPos.z + 0.001 > centerDepth) {
            sssdepth = max0(centerShadowPos.z - centerDepth);
            c = 1;
        }
        for(int i = 0; i < sampleCount - 1; i++) {
            float fi = float(i) + 1.0;
            vec2 offst = radius * dir * sqrt((fi + jitter) / float(sampleCount));
            vec2 coord = shadowPos.xy + offst;

            vec3 newShadowPos = shadowDistort(vec3(coord, shadowPos.z) * 2.0 - 1.0) * 0.5 + 0.5;
            if(outScreen(newShadowPos.xy)) continue;

            float dBlocker = textureLod(shadowtex1, newShadowPos.xy, 0).r;
            if(newShadowPos.z + 0.001 > dBlocker) {
                sssdepth += max0(centerShadowPos.z - dBlocker);
                c++;
            }

            dir = goldenRot * dir;
        }
        if(c < 1) return vec3(0.0);
        sssdepth /= float(c);

        float phase = getPhase(dot(worldDir, sunDir), 0.1);
        vec3 ssscolor = color * lightcol * exp(-(sssdepth * 3000.0)) * phase;

        return ssscolor * 2.0;
    }

    #include "/lib/shadow.glsl"

    void buildTBN(in vec3 n, out vec3 t, out vec3 b){
        vec3 up = (abs(n.z) < 0.999) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
        t = normalize(cross(up, n));
        b = cross(n, t);
    }/*
    vec3 SSPT(vec3 viewPos, vec3 normal) {
        vec3 tangent, bitangent;
        buildTBN(normal, tangent, bitangent);
        mat3 tbn = mat3(tangent, bitangent, normal);

        viewPos += normal * 0.1;
        vec3 col = vec3(0.0);
        for(int i = 0; i < 10; i++) {
            vec3 dir = vec3(blueNoise, blueNoise1, blueNoise2);
            dir.xy = dir.xy * 2.0 - 1.0;
            dir = normalize(dir);

            vec3 viewDir = normalize(tbn * dir);
            vec3 screenPos; bool isHit;
            screenRayTracing(viewPos, viewDir, screenPos, isHit);
            if(!isHit) continue;

            vec3 newViewPos = GetViewPosition(screenPos.xy, texture(depthtex1, screenPos.xy).r);
            vec3 worldPos = matrixMultiply(gbufferModelViewInverse, vec4(newViewPos, 1.0));
            vec3 shadowPos = WorldSpaceToShadowSpace(worldPos);
            vec3 shadow = sampleShadow(shadowPos);

            vec3 data0 = texture(colortex0, screenPos.xy).rgb;
            vec3 data1 = texture(colortex1, screenPos.xy).rgb;
            vec4 data2 = texture(colortex2, screenPos.xy);

            vec3 albedo = GammaToLinear(data0);
            vec3 worldNormal = normalDecode(data2.zw);
            vec3 viewNormal = normalize(mat3(gbufferModelView) * worldNormal);
            vec2 uv1 = remap(data1.rg, vec2(0.5 / 16.0), vec2(15.5 / 16.0), vec2(0.0), vec2(1.0));
            float blockID = data1.b * 10000.0;
            bool isLight = abs(blockID - 89.0) < 0.5;

            vec3  viewDir_pq = normalize(newViewPos - viewPos);
            float viewDis_pq = distance(newViewPos, viewPos);

            vec3 flux_q = albedo * max0(dot(worldNormal, lightDir)) * shadow;
            flux_q *= linearstep(0.035, 0.1, uv1.y);
            if(isLight) flux_q += albedo * 1.0;

            float costheta_p = max0(dot(normal,  viewDir_pq));
            float costheta_q = max0(dot(viewNormal, -viewDir_pq));

            col += flux_q / PI * costheta_p * costheta_q * (1.0 / pow2(viewDis_pq * 0.1 + 0.1)) * 0.1;
        }

        return col;
    }*/

#endif
