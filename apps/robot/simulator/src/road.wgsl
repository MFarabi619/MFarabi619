struct Camera {
    position: vec2<f32>,
    heading: f32,
    camera_height: f32,
    tan_half_fov: f32,
    aspect: f32,
    time: f32,
    pad: f32,
};
@group(0) @binding(0) var<uniform> cam: Camera;

struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) ndc: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VsOut {
    let uv = vec2<f32>(f32((vi << 1u) & 2u), f32(vi & 2u));
    let pos = uv * 2.0 - 1.0;
    var out: VsOut;
    out.clip = vec4<f32>(pos.x, pos.y, 0.0, 1.0);
    out.ndc = pos;
    return out;
}

const ROW_SPACING: f32 = 0.34;
const HEIGHT_SCALE: f32 = 0.22;
const MAX_DIST: f32 = 90.0;
const FOG_DISTANCE: f32 = 78.0;
const SUN_DIR: vec3<f32> = vec3<f32>(0.80, 0.28, 0.22);
const SUN_COLOR: vec3<f32> = vec3<f32>(1.70, 0.82, 0.40);
const SKY_TINT: vec3<f32> = vec3<f32>(0.40, 0.50, 0.78);

// A bare drive path carved through the crop rows, with a painted guide line down its center.
const ROAD_HALF_WIDTH: f32 = 1.1;
const ROAD_EDGE: f32 = 0.28;
const STRIPE_HALF_WIDTH: f32 = 0.12;
const STRIPE_EDGE: f32 = 0.03;

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p_in: vec2<f32>) -> f32 {
    var total = 0.0;
    var amplitude = 0.5;
    var p = p_in;
    let rot = mat2x2<f32>(0.80, 0.60, -0.60, 0.80);
    for (var octave = 0; octave < 5; octave = octave + 1) {
        total = total + amplitude * value_noise(p);
        p = rot * p * 2.0;
        amplitude = amplitude * 0.5;
    }
    return total;
}

// 1.0 on the bare road, 0.0 out in the crops.
fn road_mask(world: vec2<f32>) -> f32 {
    return 1.0 - smoothstep(ROAD_HALF_WIDTH - ROAD_EDGE, ROAD_HALF_WIDTH, abs(world.y));
}

fn crop_density(world: vec2<f32>) -> f32 {
    let row = fract(world.y / ROW_SPACING);
    let ridge = 1.0 - smoothstep(0.02, 0.46, abs(row - 0.5));
    let vigor = 0.45 + 0.95 * fbm(world * 0.11);
    let clump = fbm(world * vec2<f32>(5.5, 12.0));
    let leaf = value_noise(world * vec2<f32>(28.0, 48.0));
    let detail = value_noise(world * vec2<f32>(70.0, 110.0));
    let base = clamp(ridge * vigor * (0.32 + 0.46 * clump + 0.14 * leaf + 0.08 * detail), 0.0, 1.4);
    return base * (1.0 - road_mask(world));
}

fn terrain_height(world: vec2<f32>) -> f32 {
    return HEIGHT_SCALE * crop_density(world);
}

fn terrain_normal(world: vec2<f32>) -> vec3<f32> {
    let e = 0.008;
    let hx = terrain_height(world + vec2<f32>(e, 0.0)) - terrain_height(world - vec2<f32>(e, 0.0));
    let hy = terrain_height(world + vec2<f32>(0.0, e)) - terrain_height(world - vec2<f32>(0.0, e));
    return normalize(vec3<f32>(-hx, -hy, 2.0 * e));
}

fn raymarch(origin: vec3<f32>, dir: vec3<f32>) -> f32 {
    var t = 0.05;
    var prev = t;
    for (var i = 0; i < 420; i = i + 1) {
        let p = origin + dir * t;
        if (p.z < terrain_height(p.xy)) {
            var lo = prev;
            var hi = t;
            for (var j = 0; j < 8; j = j + 1) {
                let mid = 0.5 * (lo + hi);
                let pm = origin + dir * mid;
                if (pm.z < terrain_height(pm.xy)) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }
            return hi;
        }
        prev = t;
        t = t + max(0.012, t * 0.014);
        if (t > MAX_DIST) {
            break;
        }
    }
    return -1.0;
}

fn shadow_ray(p: vec3<f32>, sun: vec3<f32>) -> f32 {
    var shade = 1.0;
    var t = 0.03;
    for (var i = 0; i < 24; i = i + 1) {
        let sp = p + sun * t;
        let diff = sp.z - terrain_height(sp.xy);
        shade = min(shade, clamp(9.0 * diff / t, 0.0, 1.0));
        if (sp.z > HEIGHT_SCALE * 1.5 || t > 4.0) {
            break;
        }
        t = t + max(0.02, t * 0.03);
    }
    return shade;
}

fn atmosphere(dir: vec3<f32>) -> vec3<f32> {
    let sun = normalize(SUN_DIR);
    let up = clamp(dir.z, 0.0, 1.0);
    let zenith = vec3<f32>(0.16, 0.20, 0.46);
    let horizon = vec3<f32>(0.95, 0.60, 0.40);
    var col = mix(horizon, zenith, pow(up, 0.40));

    let mu = max(dot(dir, sun), 0.0);
    col = col + vec3<f32>(1.35, 0.60, 0.26) * pow(mu, 4.0) * 0.70;
    col = col + vec3<f32>(1.45, 0.85, 0.42) * pow(mu, 40.0) * 1.30;
    col = col + vec3<f32>(1.70, 1.05, 0.60) * smoothstep(0.9990, 0.9996, mu) * 38.0;

    let azimuth = pow(max(dot(normalize(vec3<f32>(dir.xy, 0.0)), normalize(vec3<f32>(sun.xy, 0.0))), 0.0), 2.5);
    col = mix(col, vec3<f32>(1.25, 0.55, 0.32), pow(1.0 - up, 5.0) * azimuth * 0.60);

    if (dir.z > 0.015) {
        let cloud_uv = dir.xy / dir.z * 1.6 + cam.time * 0.01;
        let cloud = fbm(cloud_uv * 1.8);
        let cover = smoothstep(0.50, 0.85, cloud) * smoothstep(0.02, 0.22, dir.z);
        let lit = mix(vec3<f32>(0.52, 0.46, 0.52), vec3<f32>(1.35, 0.88, 0.58), pow(mu, 1.5));
        col = mix(col, lit, cover * 0.72);
    }
    return col;
}

fn surface_color(p: vec3<f32>, view: vec3<f32>) -> vec3<f32> {
    let world = p.xy;
    let density = crop_density(world);
    let normal = terrain_normal(world);
    let sun = normalize(SUN_DIR);

    let shade = shadow_ray(p, sun);
    let n_dot_l = max(dot(normal, sun), 0.0);

    let soil_grain = fbm(world * 2.2);
    let moisture = fbm(world * 0.7 + 20.0);
    let soil = mix(vec3<f32>(0.24, 0.15, 0.09), vec3<f32>(0.46, 0.33, 0.21), soil_grain)
        * mix(1.0, 0.68, smoothstep(0.4, 0.75, moisture));
    let leaf_grain = fbm(world * vec2<f32>(5.0, 11.0) + 11.0);
    let tint = fbm(world * 0.25 + 40.0);
    let crop_green = mix(vec3<f32>(0.05, 0.19, 0.03), vec3<f32>(0.42, 0.64, 0.15), leaf_grain);
    let crop = crop_green
        * mix(vec3<f32>(0.85, 0.95, 1.0), vec3<f32>(1.28, 1.02, 0.40), smoothstep(0.45, 0.85, tint));
    let cover = smoothstep(0.06, 0.5, density);
    let albedo = mix(soil, crop, cover);

    let sky_ambient = SKY_TINT * (0.32 + 0.32 * normal.z);
    let occlusion = mix(0.35, 1.0, smoothstep(0.0, 0.6, density));
    var col = albedo * (sky_ambient * occlusion + SUN_COLOR * n_dot_l * shade);

    let half = normalize(sun + view);
    let fresnel = pow(1.0 - max(dot(view, normal), 0.0), 4.0);
    let spec = pow(max(dot(normal, half), 0.0), 55.0) * (0.2 + fresnel) * shade;
    col = col + SUN_COLOR * spec * cover;

    let back = pow(max(dot(view, -sun), 0.0), 3.0);
    col = col + crop * SUN_COLOR * back * cover * density * 1.1;

    // Painted guide line down the center of the bare path.
    let stripe = (1.0 - smoothstep(STRIPE_HALF_WIDTH, STRIPE_HALF_WIDTH + STRIPE_EDGE, abs(world.y)))
        * road_mask(world);
    let wear = 0.9 + 0.1 * value_noise(world * vec2<f32>(2.0, 30.0));
    col = mix(col, vec3<f32>(0.95, 0.92, 0.86) * wear, stripe);

    return col;
}

fn scene(ndc: vec2<f32>) -> vec3<f32> {
    let ch = cos(cam.heading);
    let sh = sin(cam.heading);
    let forward = vec3<f32>(ch, sh, 0.0);
    let right = vec3<f32>(sh, -ch, 0.0);
    let up = vec3<f32>(0.0, 0.0, 1.0);
    let dir = normalize(forward
        + right * (ndc.x * cam.tan_half_fov * cam.aspect)
        + up * (ndc.y * cam.tan_half_fov));
    let origin = vec3<f32>(cam.position, cam.camera_height);

    let sky = atmosphere(dir);
    if (dir.z < 0.0) {
        let t = raymarch(origin, dir);
        if (t > 0.0) {
            let p = origin + dir * t;
            let lit = surface_color(p, -dir);
            let fog = 1.0 - exp(-t / FOG_DISTANCE);
            return mix(lit, sky, fog);
        }
    }
    return sky;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp(
        (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14),
        vec3<f32>(0.0),
        vec3<f32>(1.0),
    );
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    var col = scene(in.ndc);

    col = aces(col * 1.06);
    let grade = mix(vec3<f32>(1.06, 0.90, 0.78), vec3<f32>(1.12, 0.98, 0.82), col);
    col = col * grade;
    let vignette = 1.0 - 0.34 * dot(in.ndc, in.ndc);
    col = col * vignette;
    col = pow(col, vec3<f32>(1.0 / 2.2));
    return vec4<f32>(col.x, col.y, col.z, 1.0);
}
