use std::{
    error::Error,
    fs::{self, File},
    io::BufWriter,
    path::Path,
};

use cadrum::{DVec3, Solid};
use robot_description::{
    datums::{WHEEL_TREAD_DIAMETER_MM, WHEEL_TREAD_WIDTH_MM},
    link::LinkId,
    parameters::{FRAME_LENGTH_MM, FRAME_TOP_Z_MM, FRAME_WIDTH_MM, RAIL_CROSS_HEIGHT_MM},
    placement::CAMERA_OPTICAL_RPY,
    MESH_URI_PREFIX, MM_TO_M,
};

use crate::{
    collada::write_collada,
    config::RobotYaml,
    export::TESSELLATION,
    mass_properties::LinkSummary,
    material::Material,
    Joint, JointType, Link,
};

fn hardware_params() -> String {
    use robot_description::wiring;
    let max_wheel_speed =
        wiring::MAX_LINEAR_VELOCITY_MPS / (WHEEL_TREAD_DIAMETER_MM / 2.0 * MM_TO_M);
    format!(
        r#"      <param name="rgpiod_host">{host}</param>
      <param name="rgpiod_port">{port}</param>
      <param name="gpio_chip">{chip}</param>
      <param name="pwm_frequency">{freq}</param>
      <param name="max_wheel_speed">{max_wheel_speed:.4}</param>
      <param name="left_wheel">front_left_wheel_joint</param>
      <param name="left_pwm_pin">{left_pwm}</param>
      <param name="left_dir_pin">{left_dir}</param>
      <param name="left_forward_level">{left_fwd}</param>
      <param name="right_wheel">front_right_wheel_joint</param>
      <param name="right_pwm_pin">{right_pwm}</param>
      <param name="right_dir_pin">{right_dir}</param>
      <param name="right_forward_level">{right_fwd}</param>
"#,
        host = wiring::HOST,
        port = wiring::RGPIOD_PORT,
        chip = wiring::GPIO_CHIP,
        freq = wiring::PWM_FREQUENCY_HZ,
        left_pwm = wiring::LEFT_PWM_PIN,
        left_dir = wiring::LEFT_DIR_PIN,
        left_fwd = i32::from(wiring::LEFT_FORWARD_LEVEL),
        right_pwm = wiring::RIGHT_PWM_PIN,
        right_dir = wiring::RIGHT_DIR_PIN,
        right_fwd = i32::from(wiring::RIGHT_FORWARD_LEVEL),
    )
}

fn gz_ros2_control_system(namespace: &str) -> String {
    let namespace_element = if namespace.is_empty() {
        String::new()
    } else {
        format!("        <namespace>{namespace}</namespace>\n")
    };
    format!(
        r#"  <gazebo>
    <plugin filename="gz_ros2_control-system" name="gz_ros2_control::GazeboSimROS2ControlPlugin">
      <parameters>package://robot_control/config/control.yaml</parameters>
      <ros>
{namespace_element}        <remapping>~/cmd_vel:=/platform/cmd_vel</remapping>
        <remapping>~/reference:=/platform/cmd_vel</remapping>
        <remapping>~/odom:=/odom</remapping>
        <remapping>~/odometry:=/odom</remapping>
        <remapping>/tf:=tf</remapping>
        <remapping>/tf_static:=tf_static</remapping>
        <remapping>joint_states:=/joint_states</remapping>
      </ros>
    </plugin>
  </gazebo>

  <gazebo>
    <plugin filename="gz-sim-pose-publisher-system" name="gz::sim::systems::PosePublisher">
      <publish_link_pose>true</publish_link_pose>
      <publish_nested_model_pose>true</publish_nested_model_pose>
      <use_pose_vector_msg>true</use_pose_vector_msg>
      <update_frequency>50</update_frequency>
    </plugin>
  </gazebo>

"#
    )
}

fn ros2_control_block(sim: bool, namespace: &str) -> String {
    let plugin = if sim {
        "gz_ros2_control/GazeboSimSystem"
    } else {
        "robot_hardware_interfaces/RobotHardware"
    };
    let mut block =
        String::from("  <ros2_control name=\"RobotHardware\" type=\"system\">\n    <hardware>\n");
    block.push_str(&format!("      <plugin>{plugin}</plugin>\n"));
    if !sim {
        block.push_str(&hardware_params());
    }
    block.push_str("    </hardware>\n");
    for wheel_joint in [
        "front_left_wheel_joint",
        "front_right_wheel_joint",
        "rear_left_wheel_joint",
        "rear_right_wheel_joint",
    ] {
        block.push_str(&format!(
            "    <joint name=\"{wheel_joint}\">\n      <command_interface name=\"velocity\"/>\n      <state_interface name=\"position\"/>\n      <state_interface name=\"velocity\"/>\n    </joint>\n",
        ));
    }
    block.push_str("  </ros2_control>\n\n");
    if sim {
        block.push_str(&gz_ros2_control_system(namespace));
    }
    block
}

fn sim_sensor_plugins(config: &RobotYaml) -> String {
    let mut xml = String::new();
    for _camera in &config.sensors.camera {
        xml.push_str(
            r#"  <gazebo reference="camera_link">
    <sensor name="camera" type="camera">
      <update_rate>15</update_rate>
      <always_on>true</always_on>
      <frame_id>camera_optical_frame</frame_id>
      <topic>camera/image_raw</topic>
      <camera>
        <horizontal_fov>1.2217</horizontal_fov>
        <image>
          <width>1280</width>
          <height>800</height>
        </image>
        <clip>
          <near>0.1</near>
          <far>100.0</far>
        </clip>
      </camera>
    </sensor>
  </gazebo>

"#,
        );
    }
    for _gps in &config.sensors.gps {
        xml.push_str(
            r#"  <gazebo reference="gps_link">
    <sensor name="gps" type="navsat">
      <always_on>1</always_on>
      <update_rate>1</update_rate>
      <frame_id>gps_link</frame_id>
      <topic>gps/fix</topic>
    </sensor>
  </gazebo>

"#,
        );
    }
    xml
}

fn sensor_and_mount_frames(config: &RobotYaml) -> String {
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
    for camera in &config.sensors.camera {
        push_frame(
            &mut xml,
            "camera_link",
            &camera.parent,
            camera.xyz,
            camera.rpy,
        );
        // ROS REP-103 optical convention: rotate x-forward body frame into z-forward optical frame.
        push_frame(
            &mut xml,
            "camera_optical_frame",
            "camera_link",
            [0.0; 3],
            CAMERA_OPTICAL_RPY,
        );
    }
    for gps in &config.sensors.gps {
        push_frame(&mut xml, "gps_link", &gps.parent, gps.xyz, gps.rpy);
    }
    xml
}

fn push_frame(xml: &mut String, name: &str, parent: &str, xyz: [f64; 3], rpy: [f64; 3]) {
    xml.push_str(&format!("  <link name=\"{name}\"/>\n"));
    xml.push_str(&format!("  <joint name=\"{name}_joint\" type=\"fixed\">\n"));
    xml.push_str(&format!("    <parent link=\"{parent}\"/>\n"));
    xml.push_str(&format!("    <child link=\"{name}\"/>\n"));
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
    config: &RobotYaml,
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

    let mut body = String::new();
    body.push_str(&format!(
        "  <link name=\"{}\"/>\n\n",
        LinkId::BaseLink.urdf_name()
    ));

    for link in links {
        body.push_str(&format!("  <link name=\"{}\">\n", link.id.urdf_name()));
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
            body.push_str(&format!(
                "    <visual><geometry><mesh filename=\"{MESH_URI_PREFIX}{mesh_filename}\"/></geometry></visual>\n",
            ));
        }
        if let Some(collision) = collision_xml(link.id) {
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
        write_joint_xml(&mut body, joint, links);
    }
    body.push_str(&sensor_and_mount_frames(config));

    let header = "<?xml version=\"1.0\"?>\n<?xml-model href=\"https://raw.githubusercontent.com/ros/urdfdom/master/xsd/urdf.xsd\" ?>\n<robot name=\"robot\">\n\n";
    let namespace = &config.system.namespace;
    let real = format!("{header}{body}{}</robot>\n", ros2_control_block(false, namespace));
    let sim = format!(
        "{header}{body}{}{}</robot>\n",
        sim_sensor_plugins(config),
        ros2_control_block(true, namespace)
    );

    let urdf_directory = package_directory.join("urdf");
    fs::create_dir_all(&urdf_directory)?;
    fs::write(urdf_directory.join("robot.urdf"), real)?;
    fs::write(urdf_directory.join("robot.sim.urdf"), sim)?;
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
