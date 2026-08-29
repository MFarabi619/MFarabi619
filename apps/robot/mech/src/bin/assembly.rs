use std::{error::Error, fs};

use glam::DVec3;
use robot_description::{
    dimensions::{self, Dimensions},
    placement::joint_table,
};
use robot_description::{
    assembly, config, export, mass_properties, mass_properties::LinkSummary, robot_root,
    time_it, urdf, Link, MM_TO_M,
};

fn camera_center_mm(robot_config: &config::RobotConfig) -> Option<DVec3> {
    robot_config
        .sensors
        .camera
        .iter()
        .find(|camera| camera.launch_enabled)
        .map(|camera| DVec3::from_array(camera.xyz) / MM_TO_M)
}

fn main() -> Result<(), Box<dyn Error>> {
    let robot_root = robot_root();
    let assets_directory = robot_root.join("assets").join("meshes");
    fs::create_dir_all(&assets_directory)?;

    let mut robot_names: Vec<_> = fs::read_dir(robot_root.join("machines"))?
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.path().join("robot.yaml").is_file())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    robot_names.sort();

    for (name, _) in dimensions::ROBOT_DIMENSIONS {
        if !robot_names.iter().any(|robot_name| robot_name == name) {
            return Err(format!(
                "mech/src/dimensions.rs lists {name} but machines/{name}/robot.yaml does not exist"
            )
            .into());
        }
    }

    let package_directory = robot_root.join("mech");
    let joints = joint_table();
    // Keyed on the camera placement as well as the frame: robots sharing a frame
    // may still mount the camera at different heights, and reusing one assembly
    // across them would bake the first robot's camera into all of them.
    type AssemblyKey = (Dimensions, Option<DVec3>);
    let mut assemblies: Vec<(AssemblyKey, Vec<Link>, Vec<LinkSummary>)> = Vec::new();
    let mut written_glbs: Vec<Option<std::path::PathBuf>> = Vec::new();
    for robot_name in &robot_names {
        let robot_dimensions = dimensions::for_robot(robot_name).ok_or_else(|| {
            format!("machines/{robot_name} has no entry in mech/src/dimensions.rs")
        })?;
        let robot_config =
            config::load(&robot_root.join(format!("machines/{robot_name}/robot.yaml")))?;
        let camera_center_mm = camera_center_mm(&robot_config);
        let assembly_key = (robot_dimensions, camera_center_mm);
        let assembly_index = match assemblies
            .iter()
            .position(|(built, _, _)| *built == assembly_key)
        {
            Some(index) => index,
            None => {
                let links = assembly::robot(&robot_dimensions, camera_center_mm)?;
                let summaries: Vec<LinkSummary> =
                    links.iter().map(mass_properties::summarize).collect();
                assemblies.push((assembly_key, links, summaries));
                written_glbs.push(None);
                assemblies.len() - 1
            }
        };
        let (_, links, summaries) = &assemblies[assembly_index];
        time_it!(
            "urdf write",
            urdf::write(
                links,
                &joints,
                summaries,
                &robot_config,
                robot_name,
                &robot_dimensions,
                &package_directory,
            )
        )?;
        println!(
            "wrote {}",
            package_directory
                .join("urdf")
                .join(robot_name)
                .join("robot.urdf")
                .display()
        );
        let glb = assets_directory.join(format!("{robot_name}.glb"));
        match &written_glbs[assembly_index] {
            Some(source) => {
                fs::copy(source, &glb)?;
                println!("wrote {}", glb.display());
            }
            None => {
                export::write_glb(links, &glb)?;
                written_glbs[assembly_index] = Some(glb);
            }
        }
    }

    if let Some(((reference_dimensions, _), _, summaries)) = assemblies.first() {
        export::report_bom(summaries);
        export::report_drivetrain(reference_dimensions);
    }
    Ok(())
}
