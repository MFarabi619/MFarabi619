use std::{
    error::Error,
    fs::{self, File},
    io::BufWriter,
    path::Path,
};

use cadrum::{DMat3, DVec3, Solid};
use description::{
    datums::{WHEEL_TREAD_DIAMETER_MM, WHEEL_TREAD_WIDTH_MM},
    link::LinkId,
    parameters::{FRAME_LENGTH_MM, FRAME_TOP_Z_MM, FRAME_WIDTH_MM, RAIL_CROSS_HEIGHT_MM},
    MESH_URI_PREFIX, MM3_TO_M3, MM5_TO_M5, MM_TO_M,
};

use crate::{
    collada::write_collada,
    export::TESSELLATION,
    material::{dominant_material, Material},
    Joint, JointType, Link,
};

pub fn write(
    links: &[Link],
    joints: &[Joint],
    package_directory: &Path,
) -> Result<(), Box<dyn Error>> {
    let meshes_directory = package_directory.join("meshes");
    if meshes_directory.exists() {
        for entry in fs::read_dir(&meshes_directory)? {
            let path = entry?.path();
            if matches!(
                path.extension().and_then(|ext| ext.to_str()),
                Some("stl" | "glb" | "dae")
            ) {
                fs::remove_file(&path)?;
            }
        }
    } else {
        fs::create_dir_all(&meshes_directory)?;
    }

    let mut xml = String::new();
    xml.push_str("<?xml version=\"1.0\"?>\n<robot name=\"robot\">\n\n");
    xml.push_str(&format!(
        "  <link name=\"{}\"/>\n\n",
        LinkId::BaseLink.urdf_name()
    ));

    for link in links {
        xml.push_str(&format!("  <link name=\"{}\">\n", link.id.urdf_name()));
        if !link.solids.is_empty() {
            let mesh_filename = format!("{}.dae", link.id.urdf_name());
            let local_solids: Vec<Solid> = link
                .solids
                .iter()
                .map(|solid| {
                    solid
                        .clone()
                        .translate(-link.origin_world)
                        .scale(DVec3::ZERO, MM_TO_M)
                })
                .collect();
            let mesh = Solid::mesh(&local_solids, TESSELLATION)?;
            let mut writer = BufWriter::new(File::create(meshes_directory.join(&mesh_filename))?);
            write_collada(&mesh, Material::pbr_for_rgb, &mut writer)?;
            xml.push_str(&format!(
                "    <visual><geometry><mesh filename=\"{MESH_URI_PREFIX}{mesh_filename}\"/></geometry></visual>\n",
            ));
        }
        if let Some(collision) = collision_xml(link.id) {
            xml.push_str(&collision);
        }
        if let Some(inertial) = inertial_xml(link) {
            xml.push_str(&inertial);
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

fn collision_xml(id: LinkId) -> Option<String> {
    match id {
        LinkId::WheelFrontLeft
        | LinkId::WheelFrontRight
        | LinkId::WheelRearLeft
        | LinkId::WheelRearRight => Some(format!(
            "    <collision><origin rpy=\"{:.4} 0 0\"/><geometry><cylinder radius=\"{:.4}\" length=\"{:.4}\"/></geometry></collision>\n",
            std::f64::consts::FRAC_PI_2,
            WHEEL_TREAD_DIAMETER_MM / 2.0 * MM_TO_M,
            WHEEL_TREAD_WIDTH_MM * MM_TO_M,
        )),
        LinkId::Chassis => Some(format!(
            "    <collision><origin xyz=\"0 0 {:.4}\"/><geometry><box size=\"{:.4} {:.4} {:.4}\"/></geometry></collision>\n",
            (FRAME_TOP_Z_MM - RAIL_CROSS_HEIGHT_MM / 2.0) * MM_TO_M,
            FRAME_LENGTH_MM * MM_TO_M,
            FRAME_WIDTH_MM * MM_TO_M,
            RAIL_CROSS_HEIGHT_MM * MM_TO_M,
        )),
        _ => None,
    }
}

fn inertial_xml(link: &Link) -> Option<String> {
    let mut mass = 0.0;
    let mut weighted_center = DVec3::ZERO;
    let mut inertia_about_world_origin = DMat3::ZERO;
    for solid in &link.solids {
        let Some(material) = dominant_material(solid) else {
            continue;
        };
        let density = material.density_kg_per_m3();
        let solid_mass = solid.volume().abs() * MM3_TO_M3 * density;
        mass += solid_mass;
        weighted_center += solid_mass * (solid.center() * MM_TO_M);
        inertia_about_world_origin += solid.inertia() * (density * MM5_TO_M5);
    }
    if mass <= 0.0 {
        return None;
    }

    let center = weighted_center / mass;
    let parallel_axis_shift = center.length_squared() * DMat3::IDENTITY
        - DMat3::from_cols(center * center.x, center * center.y, center * center.z);
    let inertia = inertia_about_world_origin - parallel_axis_shift * mass;
    let origin = center - link.origin_world * MM_TO_M;
    Some(format!(
        concat!(
            "    <inertial>\n",
            "      <origin xyz=\"{:.4} {:.4} {:.4}\"/>\n",
            "      <mass value=\"{:.4}\"/>\n",
            "      <inertia ixx=\"{:.6e}\" ixy=\"{:.6e}\" ixz=\"{:.6e}\" iyy=\"{:.6e}\" iyz=\"{:.6e}\" izz=\"{:.6e}\"/>\n",
            "    </inertial>\n",
        ),
        origin.x,
        origin.y,
        origin.z,
        mass,
        inertia.x_axis.x,
        inertia.y_axis.x,
        inertia.z_axis.x,
        inertia.y_axis.y,
        inertia.z_axis.y,
        inertia.z_axis.z,
    ))
}

fn write_joint_xml(xml: &mut String, joint: &Joint, links: &[Link]) {
    let child_origin_world = links
        .iter()
        .find(|link| link.id == joint.child)
        .expect("joint child must correspond to a Link in `links`")
        .origin_world;
    // Parent may be base_link (not present in `links`, assume world origin).
    let parent_origin_world = links
        .iter()
        .find(|link| link.id == joint.parent)
        .map(|link| link.origin_world)
        .unwrap_or(DVec3::ZERO);
    let joint_origin_meters = (child_origin_world - parent_origin_world) * MM_TO_M;
    let type_str = match joint.joint_type {
        JointType::Fixed => "fixed",
        JointType::Continuous => "continuous",
    };
    xml.push_str(&format!(
        "  <joint name=\"{}\" type=\"{}\">\n",
        joint.name, type_str
    ));
    xml.push_str(&format!(
        "    <parent link=\"{}\"/>\n",
        joint.parent.urdf_name()
    ));
    xml.push_str(&format!(
        "    <child link=\"{}\"/>\n",
        joint.child.urdf_name()
    ));
    let rpy = joint.rpy.unwrap_or([0.0; 3]);
    xml.push_str(&format!(
        "    <origin xyz=\"{:.4} {:.4} {:.4}\" rpy=\"{:.4} {:.4} {:.4}\"/>\n",
        joint_origin_meters.x, joint_origin_meters.y, joint_origin_meters.z, rpy[0], rpy[1], rpy[2],
    ));
    if let Some(axis) = joint.axis {
        xml.push_str(&format!(
            "    <axis xyz=\"{:.1} {:.1} {:.1}\"/>\n",
            axis.x, axis.y, axis.z,
        ));
    }
    xml.push_str("  </joint>\n\n");
}
