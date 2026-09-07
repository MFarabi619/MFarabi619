use std::{
    error::Error,
    fs::{self, File},
    io::BufWriter,
    path::Path,
};

use cadrum::{DVec3, Solid};
use crate::{
    datums::{CASTER_WHEEL_DIAMETER_MM, WHEEL_TREAD_DIAMETER_MM, WHEEL_TREAD_WIDTH_MM},
    dimensions::Dimensions,
    link::LinkId,
    parameters::RAIL_CROSS_HEIGHT_MM,
    placement::{caster_wheel_center, ground_z, Corner, CAMERA_OPTICAL_RPY},
    MESH_URI_PREFIX, MM_TO_M,
};

use crate::{
    collada::write_collada, config::RobotConfig, export::TESSELLATION,
    mass_properties::LinkSummary, material::Material, Joint, JointType, Link,
};

fn gz_ros2_control_system(namespace: &str) -> String {
    let namespace_element = if namespace.is_empty() {
        String::new()
    } else {
        format!("        <namespace>{namespace}</namespace>\n")
    };
    let description_topic = if namespace.is_empty() {
        String::from("/robot_description")
    } else {
        format!("/{namespace}/robot_description")
    };
    format!(
        r#"  <gazebo>
    <plugin filename="gz_ros2_control-system" name="gz_ros2_control::GazeboSimROS2ControlPlugin">
      <parameters>package://robot_control/config/control.yaml</parameters>
      <ros>
{namespace_element}        <remapping>~/cmd_vel:=platform/cmd_vel</remapping>
        <remapping>~/reference:=platform/cmd_vel</remapping>
        <remapping>~/odom:=odom</remapping>
        <remapping>~/odometry:=odom</remapping>
        <remapping>joint_states:=joint_states</remapping>
        <remapping>robot_description:={description_topic}</remapping>
      </ros>
    </plugin>
  </gazebo>

  <gazebo>
    <plugin filename="gz-sim-pose-publisher-system" name="gz::sim::systems::PosePublisher">
      <publish_link_pose>true</publish_link_pose>
      <publish_nested_model_pose>true</publish_nested_model_pose>
      <use_pose_vector_msg>true</use_pose_vector_msg>
      <update_frequency>{POSE_PUBLISHER_UPDATE_RATE_HZ}</update_frequency>
    </plugin>
  </gazebo>

"#
    )
}

#[derive(Clone, Copy, PartialEq)]
enum UrdfVariant {
    Hardware,
    Simulation,
}

fn ros2_control_block(variant: UrdfVariant, namespace: &str, drivetrain_model: &str) -> String {
    let plugin = match variant {
        UrdfVariant::Simulation => "gz_ros2_control/GazeboSimSystem",
        UrdfVariant::Hardware if drivetrain_model == "mock" => "mock_components/GenericSystem",
        UrdfVariant::Hardware => "robot_drivers/DiffDriveHardware",
    };
    let mut block = String::from(
        "  <ros2_control name=\"DiffDriveHardware\" type=\"system\">\n    <hardware>\n",
    );
    block.push_str(&format!("      <plugin>{plugin}</plugin>\n"));
    block.push_str("    </hardware>\n");
    for wheel_joint in ["rear_left_wheel_joint", "rear_right_wheel_joint"] {
        block.push_str(&format!(
            "    <joint name=\"{wheel_joint}\">\n      <command_interface name=\"velocity\"/>\n      <state_interface name=\"position\"/>\n      <state_interface name=\"velocity\"/>\n    </joint>\n",
        ));
    }
    block.push_str("  </ros2_control>\n\n");
    if variant == UrdfVariant::Simulation {
        block.push_str(&gz_ros2_control_system(namespace));
    }
    block
}

const CASTER_ROLLING_FRICTION_COEFFICIENT: f64 = 0.0;
const CASTER_LATERAL_FRICTION_COEFFICIENT: f64 = 0.2;
const CASTER_ROLLING_DIRECTION: &str = "1 0 0";
const CASTER_CONTACT_STIFFNESS_N_PER_M: f64 = 1_000_000.0;
const CASTER_CONTACT_DAMPING_N_S_PER_M: f64 = 5_000.0;
const CASTER_CONTACT_MIN_DEPTH_M: f64 = 0.001;

const POSE_PUBLISHER_UPDATE_RATE_HZ: u32 = 50;
const GPS_UPDATE_RATE_HZ: u32 = 1;
const CAMERA_CLIP_NEAR_M: f64 = 0.1;
const CAMERA_CLIP_FAR_M: f64 = 40.0;
const SIMULATION_CAMERA_WIDTH: u32 = 640;
const SIMULATION_CAMERA_HEIGHT: u32 = 480;
const SIMULATION_CAMERA_RATE_HZ: f64 = 30.0;
const CAMERA_LENS_OFFSET_M: f64 = 0.025;
const CAMERA_FOCAL_COLUMNS: f64 = 368.1;
const CAMERA_FOCAL_ROWS: f64 = 368.1;
const CAMERA_CENTER_COLUMN: f64 = 316.1;
const CAMERA_CENTER_ROW: f64 = 234.9;
const CAMERA_HORIZONTAL_FOV_RAD: f64 = 1.4312;
const DEPTH_CLIP_NEAR_M: f64 = 0.25;
const DEPTH_CLIP_FAR_M: f64 = 20.0;
const IMU_DEFAULT_RATE_HZ: f64 = 25.0;

fn caster_contact_surfaces(links: &[Link]) -> String {
    let mut xml = String::new();
    for link in links {
        if matches!(link.id, LinkId::CasterFrontLeft | LinkId::CasterFrontRight) {
            xml.push_str(&format!(
                "  <gazebo reference=\"{}\">\n    <mu1>{CASTER_ROLLING_FRICTION_COEFFICIENT}</mu1>\n    <mu2>{CASTER_LATERAL_FRICTION_COEFFICIENT}</mu2>\n    <fdir1>{CASTER_ROLLING_DIRECTION}</fdir1>\n    <kp>{CASTER_CONTACT_STIFFNESS_N_PER_M}</kp>\n    <kd>{CASTER_CONTACT_DAMPING_N_S_PER_M}</kd>\n    <minDepth>{CASTER_CONTACT_MIN_DEPTH_M}</minDepth>\n  </gazebo>\n\n",
                link.id.link_name(),
            ));
        }
    }
    xml
}

fn simulation_sensor_plugins(config: &RobotConfig) -> String {
    let mut xml = String::new();
    for (index, camera) in config.sensors.camera.iter().enumerate() {
        if !camera.launch_enabled {
            continue;
        }
        let name = format!("camera_{index}");
        let link = format!("camera_{index}_link");
        let optical = format!("camera_{index}_color_optical_frame");
        let parameters = camera
            .ros_parameters
            .get(&name)
            .or_else(|| camera.ros_parameters.values().next());
        let width = SIMULATION_CAMERA_WIDTH;
        let height = SIMULATION_CAMERA_HEIGHT;
        let update_rate = SIMULATION_CAMERA_RATE_HZ;
        let has_depth = parameters.is_some_and(|parameters| parameters.enable_depth);
        let (sensor_type, depth_clip_element) = if has_depth {
            (
                "rgbd_camera",
                format!(
                    "\n        <depth_camera>\n          <clip>\n            <near>{DEPTH_CLIP_NEAR_M}</near>\n            <far>{DEPTH_CLIP_FAR_M}</far>\n          </clip>\n        </depth_camera>"
                ),
            )
        } else {
            ("camera", String::new())
        };
        xml.push_str(&format!(
            r#"  <gazebo reference="{link}">
    <sensor name="{name}" type="{sensor_type}">
      <pose>{CAMERA_LENS_OFFSET_M} 0 0 0 0 0</pose>
      <update_rate>{update_rate}</update_rate>
      <always_on>true</always_on>
      <frame_id>{optical}</frame_id>
      <camera>
        <horizontal_fov>{CAMERA_HORIZONTAL_FOV_RAD}</horizontal_fov>
        <image>
          <width>{width}</width>
          <height>{height}</height>
        </image>
        <clip>
          <near>{CAMERA_CLIP_NEAR_M}</near>
          <far>{CAMERA_CLIP_FAR_M}</far>
        </clip>
        <lens>
          <intrinsics>
            <fx>{CAMERA_FOCAL_COLUMNS}</fx>
            <fy>{CAMERA_FOCAL_ROWS}</fy>
            <cx>{CAMERA_CENTER_COLUMN}</cx>
            <cy>{CAMERA_CENTER_ROW}</cy>
            <s>0</s>
          </intrinsics>
        </lens>{depth_clip_element}
      </camera>
    </sensor>
  </gazebo>

"#
        ));
    }
    for (index, imu) in config.sensors.imu.iter().enumerate() {
        let update_rate = imu
            .ros_parameters
            .values()
            .next()
            .and_then(|parameters| parameters.rate_hz)
            .unwrap_or(IMU_DEFAULT_RATE_HZ);
        xml.push_str(&format!(
            r#"  <gazebo reference="imu_{index}_link">
    <sensor name="imu_{index}" type="imu">
      <update_rate>{update_rate}</update_rate>
      <always_on>true</always_on>
      <frame_id>imu_{index}_link</frame_id>
    </sensor>
  </gazebo>

"#
        ));
    }
    for _gps in &config.sensors.gps {
        xml.push_str(&format!(
            r#"  <gazebo reference="gps_link">
    <sensor name="gps" type="navsat">
      <always_on>true</always_on>
      <update_rate>{GPS_UPDATE_RATE_HZ}</update_rate>
      <frame_id>gps_link</frame_id>
    </sensor>
  </gazebo>

"#,
        ));
    }
    xml
}

fn sensor_and_mount_frames(config: &RobotConfig) -> String {
    let mut xml = String::new();
    for mount in &config.mounts.camera_mount {
        push_frame(
            &mut xml,
            "camera_mount_link",
            &mount.parent,
            mount.xyz,
            mount.rpy,
        );
    }
    for (index, camera) in config.sensors.camera.iter().enumerate() {
        let link = format!("camera_{index}_link");
        let optical = format!("camera_{index}_color_optical_frame");
        push_frame(&mut xml, &link, &camera.parent, camera.xyz, camera.rpy);
        // ROS REP-103 optical convention: rotate x-forward body frame into z-forward optical frame.
        push_frame(&mut xml, &optical, &link, [0.0; 3], CAMERA_OPTICAL_RPY);
    }
    for gps in &config.sensors.gps {
        push_frame(
            &mut xml,
            LinkId::GpsLink.link_name(),
            &gps.parent,
            gps.xyz,
            gps.rpy,
        );
    }
    for (index, imu) in config.sensors.imu.iter().enumerate() {
        push_frame(
            &mut xml,
            &format!("imu_{index}_link"),
            &imu.parent,
            imu.xyz,
            imu.rpy,
        );
    }
    xml
}

fn push_frame(xml: &mut String, name: &str, parent: &str, xyz: [f64; 3], rpy: [f64; 3]) {
    xml.push_str(&format!("  <link name=\"{name}\"/>\n"));
    push_fixed_joint(xml, name, parent, xyz, rpy);
}

fn push_fixed_joint(xml: &mut String, child: &str, parent: &str, xyz: [f64; 3], rpy: [f64; 3]) {
    xml.push_str(&format!(
        "  <joint name=\"{child}_joint\" type=\"fixed\">\n"
    ));
    xml.push_str(&format!("    <parent link=\"{parent}\"/>\n"));
    xml.push_str(&format!("    <child link=\"{child}\"/>\n"));
    xml.push_str(&format!(
        "    <origin xyz=\"{:.4} {:.4} {:.4}\" rpy=\"{:.4} {:.4} {:.4}\"/>\n",
        xyz[0], xyz[1], xyz[2], rpy[0], rpy[1], rpy[2],
    ));
    xml.push_str("  </joint>\n\n");
}

pub fn write(
    links: &[Link],
    joints: &[Joint],
    summaries: &[LinkSummary],
    config: &RobotConfig,
    robot_name: &str,
    dimensions: &Dimensions,
    package_directory: &Path,
) -> Result<(), Box<dyn Error>> {
    let meshes_directory = package_directory.join("meshes").join(robot_name);
    fs::create_dir_all(&meshes_directory)?;
    for entry in fs::read_dir(&meshes_directory)? {
        let path = entry?.path();
        if matches!(
            path.extension().and_then(|ext| ext.to_str()),
            Some("stl" | "glb" | "dae")
        ) {
            fs::remove_file(&path)?;
        }
    }

    for link in links {
        if link.solids.is_empty() {
            continue;
        }
        let mesh_filename = mesh_filename(link.id);
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
    }

    let body_xml = |variant: UrdfVariant| {
        let mut body = String::new();
        body.push_str(&format!(
            "  <link name=\"{}\"/>\n\n",
            LinkId::BaseLink.link_name()
        ));

        for link in links {
            body.push_str(&format!("  <link name=\"{}\">\n", link.id.link_name()));
            if !link.solids.is_empty() {
                body.push_str(&format!(
                    "    <visual><geometry><mesh filename=\"{MESH_URI_PREFIX}{robot_name}/{}\"/></geometry></visual>\n",
                    mesh_filename(link.id),
                ));
            }
            if let Some(collision) = collision_xml(link.id, dimensions, variant) {
                body.push_str(&collision);
            }
            if link.id != LinkId::Chassis {
                if let Some(inertial) = summaries
                    .iter()
                    .find(|summary| summary.id == link.id)
                    .and_then(inertial_xml)
                {
                    body.push_str(&inertial);
                }
            }
            body.push_str("  </link>\n");
        }
        body.push('\n');

        if let Some(inertial) = summaries
            .iter()
            .find(|summary| summary.id == LinkId::Chassis)
            .and_then(inertial_xml)
        {
            body.push_str("  <link name=\"inertial_link\">\n");
            body.push_str(&inertial);
            body.push_str("  </link>\n");
            body.push_str(
                "  <joint name=\"inertial_joint\" type=\"fixed\">\n    <parent link=\"chassis\"/>\n    <child link=\"inertial_link\"/>\n    <origin xyz=\"0 0 0\" rpy=\"0 0 0\"/>\n  </joint>\n\n",
            );
        }

        for joint in joints {
            push_joint(&mut body, joint, links);
        }
        body.push_str(&sensor_and_mount_frames(config));
        body
    };

    let header = "<?xml version=\"1.0\"?>\n<?xml-model href=\"https://raw.githubusercontent.com/ros/urdfdom/master/xsd/urdf.xsd\" ?>\n<robot name=\"robot\">\n\n";
    let namespace = &config.system.namespace;
    let hardware_urdf = format!(
        "{header}{}{}</robot>\n",
        body_xml(UrdfVariant::Hardware),
        ros2_control_block(UrdfVariant::Hardware, namespace, &config.platform.drivetrain.model)
    );
    let simulation_urdf = format!(
        "{header}{}{}{}{}</robot>\n",
        body_xml(UrdfVariant::Simulation),
        caster_contact_surfaces(links),
        simulation_sensor_plugins(config),
        ros2_control_block(UrdfVariant::Simulation, namespace, &config.platform.drivetrain.model)
    );

    let urdf_directory = package_directory.join("urdf").join(robot_name);
    fs::create_dir_all(&urdf_directory)?;
    fs::write(urdf_directory.join("robot.urdf"), hardware_urdf)?;
    fs::write(urdf_directory.join("robot.sim.urdf"), simulation_urdf)?;
    Ok(())
}

fn mesh_filename(id: LinkId) -> String {
    format!("{}.dae", id.link_name())
}

fn collision_xml(id: LinkId, dimensions: &Dimensions, variant: UrdfVariant) -> Option<String> {
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
        LinkId::CasterFrontLeft | LinkId::CasterFrontRight => (variant
            == UrdfVariant::Simulation)
            .then(|| {
                let caster_wheel_radius_mm = CASTER_WHEEL_DIAMETER_MM / 2.0;
                let caster_wheel_bottom_z_mm =
                    caster_wheel_center(Corner::FrontLeft, dimensions).z
                        - caster_wheel_radius_mm;
                let contact_lift_mm =
                    ground_z(dimensions) - caster_wheel_bottom_z_mm;
                format!(
                    "    <collision><origin xyz=\"0 0 {:.4}\" rpy=\"{:.4} 0 0\"/><geometry><cylinder radius=\"{:.4}\" length=\"{:.4}\"/></geometry></collision>\n",
                    contact_lift_mm * MM_TO_M,
                    std::f64::consts::FRAC_PI_2,
                    caster_wheel_radius_mm * MM_TO_M,
                    WHEEL_TREAD_WIDTH_MM * MM_TO_M,
                )
            }),
        LinkId::Chassis => Some(format!(
            "    <collision><origin xyz=\"0 0 {:.4}\"/><geometry><box size=\"{:.4} {:.4} {:.4}\"/></geometry></collision>\n",
            (dimensions.frame_top_z_mm - RAIL_CROSS_HEIGHT_MM / 2.0) * MM_TO_M,
            dimensions.frame_length_mm * MM_TO_M,
            dimensions.frame_width_mm * MM_TO_M,
            RAIL_CROSS_HEIGHT_MM * MM_TO_M,
        )),
        _ => None,
    }
}

fn inertial_xml(summary: &LinkSummary) -> Option<String> {
    if summary.mass <= 0.0 {
        return None;
    }
    let origin = summary.center_local;
    let inertia = summary.inertia;
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
        summary.mass,
        inertia.x_axis.x,
        inertia.y_axis.x,
        inertia.z_axis.x,
        inertia.y_axis.y,
        inertia.z_axis.y,
        inertia.z_axis.z,
    ))
}

fn push_joint(xml: &mut String, joint: &Joint, links: &[Link]) {
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
    let joint_origin_m = (child_origin_world - parent_origin_world) * MM_TO_M;
    let joint_type_name = match joint.joint_type {
        JointType::Fixed => "fixed",
        JointType::Continuous => "continuous",
    };
    xml.push_str(&format!(
        "  <joint name=\"{}\" type=\"{}\">\n",
        joint.name, joint_type_name
    ));
    xml.push_str(&format!(
        "    <parent link=\"{}\"/>\n",
        joint.parent.link_name()
    ));
    xml.push_str(&format!(
        "    <child link=\"{}\"/>\n",
        joint.child.link_name()
    ));
    let rpy = joint.rpy.unwrap_or([0.0; 3]);
    xml.push_str(&format!(
        "    <origin xyz=\"{:.4} {:.4} {:.4}\" rpy=\"{:.4} {:.4} {:.4}\"/>\n",
        joint_origin_m.x, joint_origin_m.y, joint_origin_m.z, rpy[0], rpy[1], rpy[2],
    ));
    if let Some(axis) = joint.axis {
        xml.push_str(&format!(
            "    <axis xyz=\"{:.1} {:.1} {:.1}\"/>\n",
            axis.x, axis.y, axis.z,
        ));
    }
    xml.push_str("  </joint>\n\n");
}
