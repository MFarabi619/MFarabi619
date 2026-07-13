use std::{
    collections::HashMap,
    io::{self, Write},
};

use cadrum::{Color, DVec3, Mesh};

use crate::material::{Pbr, DEFAULT_MATERIAL_RGB};

const DEFAULT_COLOR: Color = Color {
    r: DEFAULT_MATERIAL_RGB[0] as f32 / 255.0,
    g: DEFAULT_MATERIAL_RGB[1] as f32 / 255.0,
    b: DEFAULT_MATERIAL_RGB[2] as f32 / 255.0,
};

const GLTF_MAGIC: u32 = 0x46546C67;
const GLTF_VERSION: u32 = 2;
const GLTF_CHUNK_JSON: u32 = 0x4E4F534A;
const GLTF_CHUNK_BIN: u32 = 0x004E4942;
const GLTF_HEADER_BYTES: usize = 12;
const GLTF_CHUNK_HEADER_BYTES: usize = 8;

const GLTF_TARGET_ARRAY_BUFFER: u32 = 34962;
const GLTF_TARGET_ELEMENT_ARRAY_BUFFER: u32 = 34963;
const GLTF_COMPONENT_UNSIGNED_SHORT: u32 = 5123;
const GLTF_COMPONENT_UNSIGNED_INT: u32 = 5125;
const GLTF_COMPONENT_FLOAT: u32 = 5126;
const GLTF_MODE_TRIANGLES: u32 = 4;

pub fn write_shaded_glb<W, F>(mesh: &Mesh, material_lookup: F, writer: &mut W) -> io::Result<()>
where
    W: Write,
    F: Fn([u8; 3]) -> Pbr,
{
    let (positions, normals, sorted_groups) = smooth_and_group(mesh);

    let needs_u32_indices = positions.len() > u16::MAX as usize;
    let mut binary_chunk: Vec<u8> = Vec::new();
    let mut buffer_views: Vec<String> = Vec::new();
    let mut accessors: Vec<String> = Vec::new();
    let mut materials: Vec<String> = Vec::new();
    let mut primitives: Vec<String> = Vec::new();

    let position_bytes = vec3s_to_f32_bytes(&positions);
    let position_buffer_view_index = push_buffer_view(
        &mut buffer_views,
        &mut binary_chunk,
        &position_bytes,
        GLTF_TARGET_ARRAY_BUFFER,
    );
    let (min, max) = vertex_bounds(&positions);
    let position_accessor_index = accessors.len();
    accessors.push(format!(
        r#"{{"bufferView":{},"componentType":{},"count":{},"type":"VEC3","min":[{},{},{}],"max":[{},{},{}]}}"#,
        position_buffer_view_index,
        GLTF_COMPONENT_FLOAT,
        positions.len(),
        format_finite_f32(min.x as f32),
        format_finite_f32(min.y as f32),
        format_finite_f32(min.z as f32),
        format_finite_f32(max.x as f32),
        format_finite_f32(max.y as f32),
        format_finite_f32(max.z as f32),
    ));

    let normal_bytes = vec3s_to_f32_bytes(&normals);
    let normal_buffer_view_index = push_buffer_view(
        &mut buffer_views,
        &mut binary_chunk,
        &normal_bytes,
        GLTF_TARGET_ARRAY_BUFFER,
    );
    let normal_accessor_index = accessors.len();
    accessors.push(format!(
        r#"{{"bufferView":{},"componentType":{},"count":{},"type":"VEC3"}}"#,
        normal_buffer_view_index,
        GLTF_COMPONENT_FLOAT,
        normals.len(),
    ));

    for (color_key, indices) in &sorted_groups {
        let index_bytes = pack_indices(indices, needs_u32_indices);
        let index_buffer_view_index = push_buffer_view(
            &mut buffer_views,
            &mut binary_chunk,
            &index_bytes,
            GLTF_TARGET_ELEMENT_ARRAY_BUFFER,
        );
        let index_accessor_index = accessors.len();
        let component_type = if needs_u32_indices {
            GLTF_COMPONENT_UNSIGNED_INT
        } else {
            GLTF_COMPONENT_UNSIGNED_SHORT
        };
        accessors.push(format!(
            r#"{{"bufferView":{},"componentType":{},"count":{},"type":"SCALAR"}}"#,
            index_buffer_view_index,
            component_type,
            indices.len(),
        ));

        let props = material_lookup(*color_key);
        let material_index = materials.len();
        let base_r = color_key[0] as f32 / 255.0;
        let base_g = color_key[1] as f32 / 255.0;
        let base_b = color_key[2] as f32 / 255.0;
        materials.push(format!(
            r#"{{"pbrMetallicRoughness":{{"baseColorFactor":[{},{},{},1],"metallicFactor":{},"roughnessFactor":{}}},"doubleSided":true}}"#,
            format_finite_f32(base_r),
            format_finite_f32(base_g),
            format_finite_f32(base_b),
            format_finite_f32(props.metallic),
            format_finite_f32(props.roughness),
        ));

        primitives.push(format!(
            r#"{{"attributes":{{"POSITION":{},"NORMAL":{}}},"indices":{},"mode":{},"material":{}}}"#,
            position_accessor_index,
            normal_accessor_index,
            index_accessor_index,
            GLTF_MODE_TRIANGLES,
            material_index,
        ));
    }

    let mut members: Vec<String> =
        vec![r#""asset":{"version":"2.0","generator":"cad shaded glb"}"#.to_string()];
    if !binary_chunk.is_empty() {
        members.push(format!(
            r#""buffers":[{{"byteLength":{}}}]"#,
            binary_chunk.len()
        ));
    }
    if !buffer_views.is_empty() {
        members.push(format!(r#""bufferViews":[{}]"#, buffer_views.join(",")));
    }
    if !accessors.is_empty() {
        members.push(format!(r#""accessors":[{}]"#, accessors.join(",")));
    }
    if !materials.is_empty() {
        members.push(format!(r#""materials":[{}]"#, materials.join(",")));
    }
    if !primitives.is_empty() {
        members.push(format!(
            r#""meshes":[{{"primitives":[{}]}}]"#,
            primitives.join(",")
        ));
        members.push(r#""nodes":[{"mesh":0}]"#.to_string());
        members.push(r#""scenes":[{"nodes":[0]}]"#.to_string());
        members.push(r#""scene":0"#.to_string());
    }
    let json_str = format!("{{{}}}", members.join(","));

    let mut json_bytes = json_str.into_bytes();
    while json_bytes.len() % 4 != 0 {
        json_bytes.push(b' ');
    }
    while binary_chunk.len() % 4 != 0 {
        binary_chunk.push(0);
    }

    let has_binary_chunk = !binary_chunk.is_empty();
    let total_length = GLTF_HEADER_BYTES
        + GLTF_CHUNK_HEADER_BYTES
        + json_bytes.len()
        + if has_binary_chunk {
            GLTF_CHUNK_HEADER_BYTES + binary_chunk.len()
        } else {
            0
        };

    writer.write_all(&GLTF_MAGIC.to_le_bytes())?;
    writer.write_all(&GLTF_VERSION.to_le_bytes())?;
    writer.write_all(&(total_length as u32).to_le_bytes())?;

    writer.write_all(&(json_bytes.len() as u32).to_le_bytes())?;
    writer.write_all(&GLTF_CHUNK_JSON.to_le_bytes())?;
    writer.write_all(&json_bytes)?;

    if has_binary_chunk {
        writer.write_all(&(binary_chunk.len() as u32).to_le_bytes())?;
        writer.write_all(&GLTF_CHUNK_BIN.to_le_bytes())?;
        writer.write_all(&binary_chunk)?;
    }

    Ok(())
}

pub(crate) fn smooth_and_group(mesh: &Mesh) -> (Vec<DVec3>, Vec<DVec3>, Vec<([u8; 3], Vec<u32>)>) {
    let triangle_count = mesh.indices.len() / 3;
    let mut positions: Vec<DVec3> = Vec::new();
    let mut normal_accum: Vec<DVec3> = Vec::new();
    let mut vertex_map: HashMap<(usize, u64), u32> = HashMap::new();
    let mut indices_by_color: HashMap<[u8; 3], Vec<u32>> = HashMap::new();

    for triangle_index in 0..triangle_count {
        let face_id = mesh.face_ids[triangle_index];
        let source_vertex_indices = [
            mesh.indices[triangle_index * 3],
            mesh.indices[triangle_index * 3 + 1],
            mesh.indices[triangle_index * 3 + 2],
        ];
        let triangle_vertices = [
            mesh.vertices[source_vertex_indices[0]],
            mesh.vertices[source_vertex_indices[1]],
            mesh.vertices[source_vertex_indices[2]],
        ];
        let area_weighted_normal = (triangle_vertices[1] - triangle_vertices[0])
            .cross(triangle_vertices[2] - triangle_vertices[0]);

        let mut new_indices = [0u32; 3];
        for corner_index in 0..3 {
            let new_vertex_index = *vertex_map
                .entry((source_vertex_indices[corner_index], face_id))
                .or_insert_with(|| {
                    let assigned = positions.len() as u32;
                    positions.push(triangle_vertices[corner_index]);
                    normal_accum.push(DVec3::ZERO);
                    assigned
                });
            normal_accum[new_vertex_index as usize] += area_weighted_normal;
            new_indices[corner_index] = new_vertex_index;
        }

        let color = mesh
            .colormap
            .get(&face_id)
            .copied()
            .unwrap_or(DEFAULT_COLOR);
        let color_key = [
            (color.r.clamp(0.0, 1.0) * 255.0) as u8,
            (color.g.clamp(0.0, 1.0) * 255.0) as u8,
            (color.b.clamp(0.0, 1.0) * 255.0) as u8,
        ];
        let color_indices = indices_by_color.entry(color_key).or_default();
        color_indices.push(new_indices[0]);
        color_indices.push(new_indices[1]);
        color_indices.push(new_indices[2]);
    }

    let normals: Vec<DVec3> = normal_accum.iter().map(|n| n.normalize_or_zero()).collect();
    let mut color_groups: Vec<([u8; 3], Vec<u32>)> = indices_by_color.into_iter().collect();
    color_groups.sort_by_key(|(color_key, _)| *color_key);
    (positions, normals, color_groups)
}

fn push_buffer_view(
    buffer_views: &mut Vec<String>,
    binary_chunk: &mut Vec<u8>,
    data: &[u8],
    target: u32,
) -> usize {
    while binary_chunk.len() % 4 != 0 {
        binary_chunk.push(0);
    }
    let byte_offset = binary_chunk.len();
    binary_chunk.extend_from_slice(data);
    let assigned_index = buffer_views.len();
    buffer_views.push(format!(
        r#"{{"buffer":0,"byteOffset":{},"byteLength":{},"target":{}}}"#,
        byte_offset,
        data.len(),
        target,
    ));
    assigned_index
}

fn vec3s_to_f32_bytes(vectors: &[DVec3]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(vectors.len() * 12);
    for v in vectors {
        bytes.extend_from_slice(&(v.x as f32).to_le_bytes());
        bytes.extend_from_slice(&(v.y as f32).to_le_bytes());
        bytes.extend_from_slice(&(v.z as f32).to_le_bytes());
    }
    bytes
}

fn pack_indices(indices: &[u32], needs_u32_indices: bool) -> Vec<u8> {
    if needs_u32_indices {
        let mut bytes = Vec::with_capacity(indices.len() * 4);
        for &i in indices {
            bytes.extend_from_slice(&i.to_le_bytes());
        }
        bytes
    } else {
        let mut bytes = Vec::with_capacity(indices.len() * 2);
        for &i in indices {
            bytes.extend_from_slice(&(i as u16).to_le_bytes());
        }
        bytes
    }
}

fn vertex_bounds(vertices: &[DVec3]) -> (DVec3, DVec3) {
    let init = (DVec3::splat(f64::INFINITY), DVec3::splat(f64::NEG_INFINITY));
    vertices
        .iter()
        .copied()
        .fold(init, |(mn, mx), point| (mn.min(point), mx.max(point)))
}

fn format_finite_f32(x: f32) -> String {
    if x.is_finite() {
        format!("{}", x)
    } else {
        "0".to_string()
    }
}
