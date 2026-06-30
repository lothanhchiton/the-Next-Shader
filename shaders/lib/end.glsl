#ifndef END_GLSL
    #define END_GLSL a

    #define _vc1 96.0 // [4.0 6.0 8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0 156.0 214.0 256.0]
    #define _vc2 0.14 // [0.005 0.01 0.02 0.04 0.08 0.12 0.14 0.18 0.2 0.24 0.28 0.3]
    #define _vc3 0.39 // [-1.57 -0.79 -0.39 -0.265 -0.1 0.0 0.1 0.265 0.39 0.79 1.57]

    float _vcA(float x) {
        float x2 = x * x;
        return 12.207 * x2 * x2 * (1.0 - x);
    }
    float _vcB(float x) {
        return x * x * (3.0 - 2.0 * x);
    }
    float _vcC(vec2 v) {
        return atan(v.x, v.y);
    }

    mat3 _vcD(float x, float y, float z) {
        mat3 mx = mat3(1.0, 0.0, 0.0, 0.0, cos(x), sin(x), 0.0, -sin(x), cos(x));
        mat3 my = mat3(cos(y), 0.0, -sin(y), 0.0, 1.0, 0.0, sin(y), 0.0, cos(y));
        mat3 mz = mat3(cos(z), sin(z), 0.0, -sin(z), cos(z), 0.0, 0.0, 0.0, 1.0);
        return my * mx * mz;
    }

    float _vcE(vec3 p) {
        vec3 fp = floor(p);
        vec3 b = vec3(_vcB(fract(p).x), _vcB(fract(p).y), _vcB(fract(p).z));

        vec2 uv = 17.0 * fp.z + fp.xy + b.xy;
        vec2 rg = textureLod(noisetex, (uv + 0.5) / noiseTextureResolution, 0.0).rg;

        return mix(rg.x, rg.y, b.z);
    }

    vec3 _vcF(float temp) {
        temp = clamp(temp, 1000.0, 40000.0) / 100.0;
        vec3 col;

        if(temp <= 66.0) {
            col.r = 1.0;
            col.g = saturate(0.39 * log(temp) - 0.63);
        } else {
            col.r = saturate(1.29 * pow(temp - 60.0, -0.133));
            col.g = saturate(1.13 * pow(temp - 60.0, -0.075));
        }

        if(temp >= 66.0) {
            col.b = 1.0;
        } else if(temp <= 19.0) {
            col.b = 0.0;
        } else {
            col.b = saturate(0.543 * log(temp - 10.0) - 1.196);
        }

        return col;
    }

    float _vcSphereHit(vec3 rayOrigin, vec3 rayDir, float radius) {
        float b = dot(rayOrigin, rayDir);
        float c = dot(rayOrigin, rayOrigin) - radius * radius;
        float disc = b * b - c;
        if(disc < 0.0) return -1.0;
        float t = -b - sqrt(disc);
        return t;
    }

    void _vcRender(inout vec3 color, vec3 worldEyeDir, float dither, float maxWorldDist) {
        const float steps = 80.0;
        const float stepLen = 0.15;
        const float boundRadius = 6.0;

        vec3 worldOffset = cameraPosition - vec3(56.438, 329.48578, 726.225);

        vec3 eye = worldOffset / _vc1;
        eye.y = eye.y;

        vec3 rayDir = worldEyeDir;
        rayDir.y = rayDir.y;

        float maxLocalDist = maxWorldDist / _vc1;

        float hitDist = _vcSphereHit(eye, rayDir, boundRadius);
        if(hitDist < 0.0 && length(eye) > boundRadius) {
            return;
        }
        if(hitDist > maxLocalDist) {
            return;
        }
        float skipDist = max(hitDist, 0.0);

        vec3 rayPos = eye + rayDir * skipDist;

        mat3 tilt = _vcD(_vc3, 0.0, 0.0);

        float time = float(frameCounter) * 0.002;

        vec3 result = vec3(0.0);
        float transmittance = 1.0;
        rayPos += rayDir * stepLen * dither;

        float traveled = skipDist;

        for(int i = 0; i < int(steps); i++) {
            if(transmittance < 0.0001) break;
            if(traveled > maxLocalDist) break;

            vec3 tiltedPos = tilt * rayPos;

            float rPlanar = length(tiltedPos.xz);

            float omega = 0.05 / pow(max(rPlanar, 0.15), 1.5);
            float angle = time * omega;

            float ca = cos(angle);
            float sa = sin(angle);
            vec3 discPos = vec3(
                tiltedPos.x * ca - tiltedPos.z * sa,
                tiltedPos.y,
                tiltedPos.x * sa + tiltedPos.z * ca
            );

            float r = length(discPos);
            float h = discPos.y;

            float discGradient = saturate(1.09 - r * 0.15);

            float thickness = 1.0 - (abs(h) / discGradient) * 20.0;
            float baseDensity = _vcA(discGradient) * (1.0 - discGradient) * 12.207;
            float hazeDensity = saturate(thickness + 1.0) * 0.03 / (h * h + _vcA(r - 0.1) * 1e-3);
            float density = saturate(mix(baseDensity * saturate(thickness), hazeDensity * hazeDensity, 0.1));

            if(density > 0.0001) {
                vec3 discCoord = vec3(r * 30.0, 0.0, h * 8.0);

                float fbm = 0.0;
                float alpha = 1.0;
                vec3 bias = time * vec3(0.0, 0.1, 0.0);

                for(int j = 0; j < 4; j++) {
                    fbm += alpha * _vcE(discCoord);
                    discCoord = (discCoord + bias) * 2.7;
                    alpha *= 0.75;
                }
                fbm = saturate(fbm * 1.5 - 2.25) * 0.9 + 0.1;

                density *= fbm * baseDensity;

                float glowGradient = _vcA(1.0 - discGradient);
                float glowStrength = 1.0 / (glowGradient * 200.0 + 0.002);

                float glowTemperature = 2700.0 + glowStrength * 20.0;
                vec3 glow = mix(_vcF(glowTemperature), vec3(1.15, 0.75, 1.35), 0.15 - glowGradient * 0.1) * glowStrength;

                float coreRadius = 0.6;
                float coreFade = smoothstep(coreRadius, coreRadius + 0.3, r);
                glow *= coreFade;

                float stepTransmittance = exp2(-density * 7.0);
                transmittance *= stepTransmittance;

                result += (1.0 - stepTransmittance) * glow * transmittance;
            }

            vec3 prevRayPos = rayPos;
            rayDir = normalize(rayDir - normalize(rayPos) / (r * r + 1e-20) * 0.06);
            rayPos += rayDir * stepLen;
            traveled += distance(rayPos, prevRayPos);
        }

        result *= _vc2;

        color *= transmittance;
        color += result;
    }
#endif