

float getPuddleCoverage(vec3 worldPos, vec3 worldNormal, vec2 lm) {
    float NdotU = dot(worldNormal, vec3(0.0, 1.0, 0.0));
    if (NdotU < 0.85) return 0.0;

    vec2 lmr = clamp((lm - 0.03125) * 1.06667, 0.0, 1.0);

    float skyFactor = max(lmr.y * 32.0 - 31.0, 0.0);
    float blockFactor = clamp((1.0 - 1.15 * lmr.x) * 10.0, 0.0, 1.0);
    float puddleMixer = skyFactor * blockFactor * isRain;
    if (puddleMixer < 0.001) return 0.0;

    vec2 uv = worldPos.xz * 0.005;
    float form = texture2D(noisetex, uv ).b * 3.0;
          form += texture2D(noisetex, uv * 0.50 ).b * 5.0;
          form += texture2D(noisetex, uv * 0.25 ).b * 8.0;
    form *= pSqrt(wetness) * 0.5625 + 0.4375;
    form = clamp(form - 7.0, 0.0, 1.0);

    return puddleMixer * form;
}

vec3 getPuddleNormal(vec3 worldPos, mat3 tbn) {
    vec2 base = worldPos.xz * 0.1;
    vec2 wind = vec2(frameTimeCounter * 0.03);

    vec3 s1 = texture2D(noisetex, base + vec2( wind.x, wind.y )).rgb;
    vec3 s2 = texture2D(noisetex, base + vec2(-wind.x * 1.5, -wind.y )).rgb;

    const float rippleStrength = 0.03;
    vec3 tsRipple = normalize(vec3((s1.xy + s2.xy - 1.0) * rippleStrength, 1.0));

    return clamp(normalize(tbn * tsRipple), -1.0, 1.0);
}

void rainPuddles(vec3 worldPos, vec3 worldNormal, mat3 tbn, vec2 lm, inout vec3 mappedNormal, inout vec4 specularData) {
    float coverage = getPuddleCoverage(worldPos, worldNormal, lm);
    if (coverage < 0.001) return;

    vec3 rippleNormal = getPuddleNormal(worldPos, tbn);

    mappedNormal = normalize(mix(mappedNormal, rippleNormal, coverage));

    specularData.r = mix(specularData.r, 0.90, coverage);
    specularData.g = mix(specularData.g, 0.02, coverage);
}