use std::collections::{BTreeMap, HashMap};
use std::error::Error;
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::path::Path;

use cadrum::{Color, Mesh, Solid, Tessellation};

use crate::link::{Joint, JointType, Link, LinkId};
use crate::material::DEFAULT_MATERIAL_RGB;

const TESSELLATION: Tessellation = Tessellation {
    deflection_linear: 0.01,
    deflection_angular: 0.05,
    relative_linear: true,
    is_parallel: true,
};

pub fn write(
    links: &[Link],
    joints: &[Joint],
    package_directory: &Path,
    material_name_for: fn([u8; 3]) -> &'static str,
) -> Result<(), Box<dyn Error>> {
    let meshes_directory = package_directory.join("meshes");
    if meshes_directory.exists() {
        for entry in fs::read_dir(&meshes_directory)? {
            let path = entry?.path();
            if path.extension().and_then(|ext| ext.to_str()) == Some("stl") {
                fs::remove_file(&path)?;
            }
        }
    } else {
        fs::create_dir_all(&meshes_directory)?;
    }

    let mut link_material_stls: HashMap<LinkId, Vec<String>> = HashMap::new();
    let mut all_materials: BTreeMap<String, [u8; 3]> = BTreeMap::new();

    for link in links {
        let local_solids: Vec<Solid> = link
            .solids
            .iter()
            .cloned()
            .map(|solid| solid.translate(-link.origin_world))
            .collect();
        let mesh = Solid::mesh(&local_solids, TESSELLATION)?;

        let mut colors_by_material: BTreeMap<String, Vec<[u8; 3]>> = BTreeMap::new();
        let mut representative_color_for_material: BTreeMap<String, [u8; 3]> = BTreeMap::new();
        for color in unique_triangle_colors(&mesh) {
            let material_name = sanitize(material_name_for(color));
            representative_color_for_material.entry(material_name.clone()).or_insert(color);
            colors_by_material.entry(material_name).or_default().push(color);
        }

        let mut per_link_names: Vec<String> = Vec::new();
        for (material_name, color_keys) in colors_by_material {
            let stl_filename = format!("{}_{}.stl", link.id.urdf_name(), material_name);
            let stl_path = meshes_directory.join(&stl_filename);
            let mut writer = BufWriter::new(File::create(&stl_path)?);
            write_stl_subset(&mesh, &color_keys, &mut writer)?;
            writer.flush()?;
            let representative = representative_color_for_material[&material_name];
            all_materials.entry(material_name.clone()).or_insert(representative);
            per_link_names.push(material_name);
        }
        link_material_stls.insert(link.id, per_link_names);
    }

    let mut xml = String::new();
    xml.push_str("<?xml version=\"1.0\"?>\n<robot name=\"robot\">\n\n");

    for (material_name, color) in &all_materials {
        let rgb = normalize_rgb(*color);
        xml.push_str(&format!(
            "  <material name=\"{}\"><color rgba=\"{:.3} {:.3} {:.3} 1.0\"/></material>\n",
            material_name, rgb[0], rgb[1], rgb[2],
        ));
    }
    xml.push_str(&format!("\n  <link name=\"{}\"/>\n\n", LinkId::BaseLink.urdf_name()));

    for link in links {
        xml.push_str(&format!("  <link name=\"{}\">\n", link.id.urdf_name()));
        if let Some(names) = link_material_stls.get(&link.id) {
            for material_name in names {
                let stl_filename = format!("{}_{}.stl", link.id.urdf_name(), material_name);
                xml.push_str(&format!(
                    "    <visual><geometry><mesh filename=\"package://robot/meshes/{}\" scale=\"0.001 0.001 0.001\"/></geometry><material name=\"{}\"/></visual>\n",
                    stl_filename, material_name,
                ));
            }
        }
        xml.push_str("  </link>\n");
    }
    xml.push('\n');

    for joint in joints {
        write_joint_xml(&mut xml, joint, links);
    }
    xml.push_str("</robot>\n");
    fs::write(package_directory.join("urdf").join("robot.urdf"), xml)?;
    Ok(())
}

fn write_joint_xml(xml: &mut String, joint: &Joint, links: &[Link]) {
    let child_origin_world = links
        .iter()
        .find(|link| link.id == joint.child)
        .expect("joint child must correspond to a Link in `links`")
        .origin_world;
    let child_origin_meters = child_origin_world / 1000.0;
    let type_str = match joint.joint_type {
        JointType::Fixed => "fixed",
        JointType::Continuous => "continuous",
    };
    xml.push_str(&format!("  <joint name=\"{}\" type=\"{}\">\n", joint.name, type_str));
    xml.push_str(&format!("    <parent link=\"{}\"/>\n", joint.parent.urdf_name()));
    xml.push_str(&format!("    <child link=\"{}\"/>\n", joint.child.urdf_name()));
    let rpy = joint.rpy.unwrap_or([0.0; 3]);
    xml.push_str(&format!(
        "    <origin xyz=\"{:.4} {:.4} {:.4}\" rpy=\"{:.4} {:.4} {:.4}\"/>\n",
        child_origin_meters.x,
        child_origin_meters.y,
        child_origin_meters.z,
        rpy[0],
        rpy[1],
        rpy[2],
    ));
    if let Some(axis) = joint.axis {
        xml.push_str(&format!(
            "    <axis xyz=\"{:.1} {:.1} {:.1}\"/>\n",
            axis.x, axis.y, axis.z,
        ));
    }
    xml.push_str("  </joint>\n\n");
}

fn unique_triangle_colors(mesh: &Mesh) -> Vec<[u8; 3]> {
    let triangle_count = mesh.indices.len() / 3;
    let mut seen: BTreeMap<[u8; 3], ()> = BTreeMap::new();
    for triangle_index in 0..triangle_count {
        let face_id = mesh.face_ids[triangle_index];
        let color = mesh.colormap.get(&face_id).copied();
        let color_key = color.map(quantize_color).unwrap_or(DEFAULT_MATERIAL_RGB);
        seen.insert(color_key, ());
    }
    seen.into_keys().collect()
}

fn write_stl_subset<W: Write>(
    mesh: &Mesh,
    color_keys: &[[u8; 3]],
    writer: &mut W,
) -> io::Result<()> {
    let triangle_count = mesh.indices.len() / 3;
    let mut matching: Vec<usize> = Vec::new();
    for triangle_index in 0..triangle_count {
        let face_id = mesh.face_ids[triangle_index];
        let this_color = mesh.colormap.get(&face_id).copied();
        let this_key = this_color.map(quantize_color).unwrap_or(DEFAULT_MATERIAL_RGB);
        if color_keys.contains(&this_key) {
            matching.push(triangle_index);
        }
    }

    writer.write_all(&[0u8; 80])?;
    writer.write_all(&(matching.len() as u32).to_le_bytes())?;
    for &triangle_index in &matching {
        let i0 = mesh.indices[triangle_index * 3];
        let i1 = mesh.indices[triangle_index * 3 + 1];
        let i2 = mesh.indices[triangle_index * 3 + 2];
        let v0 = mesh.vertices[i0];
        let v1 = mesh.vertices[i1];
        let v2 = mesh.vertices[i2];
        let normal = (v1 - v0).cross(v2 - v0).normalize_or_zero();
        for coordinate in [normal.x, normal.y, normal.z] {
            writer.write_all(&(coordinate as f32).to_le_bytes())?;
        }
        for vertex in [v0, v1, v2] {
            for coordinate in [vertex.x, vertex.y, vertex.z] {
                writer.write_all(&(coordinate as f32).to_le_bytes())?;
            }
        }
        writer.write_all(&0u16.to_le_bytes())?;
    }
    Ok(())
}

fn quantize_color(color: Color) -> [u8; 3] {
    [
        (color.r.clamp(0.0, 1.0) * 255.0) as u8,
        (color.g.clamp(0.0, 1.0) * 255.0) as u8,
        (color.b.clamp(0.0, 1.0) * 255.0) as u8,
    ]
}

fn normalize_rgb(color: [u8; 3]) -> [f32; 3] {
    [color[0] as f32 / 255.0, color[1] as f32 / 255.0, color[2] as f32 / 255.0]
}

fn sanitize(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' })
        .collect()
}
