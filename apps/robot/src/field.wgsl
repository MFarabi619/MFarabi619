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

const ROW_SPACING: f32 = 0.40;
const PLANT_SPACING: f32 = 0.30;
const PLANT_RADIUS: f32 = 0.145;
const PLANT_HEIGHT: f32 = 0.16;
const PLANT_JITTER: f32 = 0.05;
const BED_PITCH: f32 = 1.60;
const BED_PLANTED_FRACTION: f32 = 0.52;
const TARP_HALF_WIDTH: f32 = 0.19;
const LEAF_BUMP: f32 = 2.2;
const MAX_DISTANCE: f32 = 90.0;
const FOG_DISTANCE: f32 = 120.0;
const SUN_DIR: vec3<f32> = vec3<f32>(0.60, 0.29, 0.42);
const SUN_COLOR: vec3<f32> = vec3<f32>(1.18, 1.14, 1.02);
const SKY_TINT: vec3<f32> = vec3<f32>(0.50, 0.58, 0.72);

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

fn crinkle(world: vec2<f32>) -> f32 {
    return fbm(world * 58.0);
}

struct Plant {
    distance: f32,
    radius: f32,
    redness: f32,
    planted: f32,
    row_center: f32,
    tint: f32,
};

fn nearest_plant(world: vec2<f32>) -> Plant {
    let col = floor(world.x / PLANT_SPACING + 0.5);
    let row = floor(world.y / ROW_SPACING + 0.5);
    let cell = vec2<f32>(col, row);

    let jx = (hash2(cell + vec2<f32>(3.1, 1.7)) - 0.5) * 2.0 * PLANT_JITTER;
    let jy = (hash2(cell + vec2<f32>(7.7, 2.3)) - 0.5) * 2.0 * PLANT_JITTER;
    let center = vec2<f32>(col * PLANT_SPACING + jx, row * ROW_SPACING + jy);

    var p: Plant;
    p.row_center = row * ROW_SPACING;
    p.distance = length(world - center);
    p.radius = PLANT_RADIUS * (0.80 + 0.40 * hash2(cell + vec2<f32>(1.7, 9.2)));
    p.planted = select(0.0, 1.0, fract(p.row_center / BED_PITCH) < BED_PLANTED_FRACTION);
    p.tint = hash2(cell + vec2<f32>(2.9, 6.4));

    let parity = step(0.25, fract((col + row * 3.0) * 0.5));
    let flip = step(0.82, hash2(cell + vec2<f32>(5.3, 4.1)));
    p.redness = abs(parity - flip);
    return p;
}

fn terrain_height(world: vec2<f32>) -> f32 {
    let p = nearest_plant(world);
    if (p.planted < 0.5) {
        return 0.0;
    }
    let d = p.distance / p.radius;
    let dome = 1.0 - smoothstep(0.5, 1.0, d);
    let lobe = 0.72 + 0.28 * fbm(world * 9.0);
    let crink = 0.010 * (crinkle(world) - 0.5);
    return PLANT_HEIGHT * dome * lobe + crink * dome;
}

fn terrain_normal(world: vec2<f32>) -> vec3<f32> {
    let e = 0.008;
    let hx = terrain_height(world + vec2<f32>(e, 0.0)) - terrain_height(world - vec2<f32>(e, 0.0));
    let hy = terrain_height(world + vec2<f32>(0.0, e)) - terrain_height(world - vec2<f32>(0.0, e));
    return normalize(vec3<f32>(-hx, -hy, 2.0 * e));
}

fn leaf_normal(world: vec2<f32>, base: vec3<f32>) -> vec3<f32> {
    let e = 0.004;
    let dx = crinkle(world + vec2<f32>(e, 0.0)) - crinkle(world - vec2<f32>(e, 0.0));
    let dy = crinkle(world + vec2<f32>(0.0, e)) - crinkle(world - vec2<f32>(0.0, e));
    return normalize(base + vec3<f32>(-dx, -dy, 0.0) * LEAF_BUMP);
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
        if (t > MAX_DISTANCE) {
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
        if (sp.z > PLANT_HEIGHT * 1.5 || t > 4.0) {
            break;
        }
        t = t + max(0.02, t * 0.03);
    }
    return shade;
}

fn atmosphere(dir: vec3<f32>) -> vec3<f32> {
    let sun = normalize(SUN_DIR);
    let up = clamp(dir.z, 0.0, 1.0);
    let zenith = vec3<f32>(0.18, 0.40, 0.80);
    let sky = vec3<f32>(0.47, 0.67, 0.92);
    var col = mix(sky, zenith, pow(up, 0.65));
    col = mix(col, vec3<f32>(0.80, 0.85, 0.90), 0.5 * pow(1.0 - up, 16.0));

    let mu = max(dot(dir, sun), 0.0);
    col = col + vec3<f32>(1.00, 0.96, 0.84) * pow(mu, 260.0) * 9.0;
    col = col + vec3<f32>(0.95, 0.90, 0.78) * pow(mu, 8.0) * 0.30;

    if (dir.z > 0.02) {
        let cloud_uv = dir.xy / dir.z * 1.4 + cam.time * 0.008;
        let cloud = fbm(cloud_uv * 1.6);
        let cover = smoothstep(0.55, 0.90, cloud) * smoothstep(0.02, 0.30, dir.z);
        col = mix(col, vec3<f32>(1.00, 1.00, 1.02), cover * 0.55);
    }
    return col;
}

fn surface_color(p: vec3<f32>, view: vec3<f32>) -> vec3<f32> {
    let world = p.xy;
    let plant = nearest_plant(world);
    let height = terrain_height(world);
    let cover = smoothstep(0.03, 0.11, height);

    let base_normal = terrain_normal(world);
    let normal = normalize(mix(base_normal, leaf_normal(world, base_normal), cover));
    let sun = normalize(SUN_DIR);
    let shade = shadow_ray(p, sun);
    let n_dot_l = max(dot(normal, sun), 0.0);

    let grain = fbm(world * 3.0);
    let dirt = mix(vec3<f32>(0.28, 0.22, 0.15), vec3<f32>(0.52, 0.44, 0.31), grain);
    let bed_id = floor(plant.row_center / BED_PITCH + 0.5);
    let tarp_present = step(0.40, hash2(vec2<f32>(bed_id, 17.0)));
    let bed_distance = abs(world.y - plant.row_center);
    let tarp_cover = plant.planted * tarp_present
        * (1.0 - smoothstep(TARP_HALF_WIDTH - 0.05, TARP_HALF_WIDTH, bed_distance));
    let speck = value_noise(world * 40.0);
    let tarp = mix(vec3<f32>(0.035, 0.035, 0.040), dirt, 0.12 * speck);
    let ground = mix(dirt, tarp, tarp_cover);

    let tip = crinkle(world);
    let mottle = fbm(world * 2.5 + 30.0);
    let green = mix(vec3<f32>(0.09, 0.15, 0.04), vec3<f32>(0.38, 0.52, 0.15), tip);
    let red = mix(vec3<f32>(0.09, 0.02, 0.04), vec3<f32>(0.33, 0.09, 0.10), tip);
    var leaf = mix(green, red, plant.redness);
    leaf = leaf * (0.82 + 0.30 * mottle) * (0.85 + 0.30 * plant.tint);
    let luma = dot(leaf, vec3<f32>(0.299, 0.587, 0.114));
    leaf = mix(vec3<f32>(luma), leaf, 0.82);

    let albedo = mix(ground, leaf, cover);

    let leaf_ao = mix(0.55, 1.0, smoothstep(0.25, 0.75, tip));
    let ao = mix(0.65, 1.0, cover) * mix(1.0, leaf_ao, cover);
    let sky_ambient = SKY_TINT * (0.42 + 0.35 * normal.z);
    var col = albedo * (sky_ambient * ao + SUN_COLOR * n_dot_l * shade);

    let half = normalize(sun + view);
    let spec = pow(max(dot(normal, half), 0.0), 18.0) * 0.06 * shade;
    col = col + SUN_COLOR * spec * cover;

    let back = pow(max(dot(view, -sun), 0.0), 2.0);
    col = col + leaf * SUN_COLOR * back * cover * 0.25;

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

    col = aces(col * 1.02);
    let vignette = 1.0 - 0.18 * dot(in.ndc, in.ndc);
    col = col * vignette;
    col = pow(col, vec3<f32>(1.0 / 2.2));
    return vec4<f32>(col.x, col.y, col.z, 1.0);
}
