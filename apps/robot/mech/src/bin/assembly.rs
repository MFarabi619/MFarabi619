use std::{error::Error, fs};

use robot_description::{
    dimensions::{self, Dimensions},
    placement::joint_table,
};
use robot_description::{
    assembly, config, export, mass_properties, mass_properties::LinkSummary, robot_root,
    time_it, urdf, Link,
};

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
    let mut assemblies: Vec<(Dimensions, Vec<Link>, Vec<LinkSummary>)> = Vec::new();
    let mut written_glbs: Vec<Option<std::path::PathBuf>> = Vec::new();
    for robot_name in &robot_names {
        let robot_dimensions = dimensions::for_robot(robot_name).ok_or_else(|| {
            format!("machines/{robot_name} has no entry in mech/src/dimensions.rs")
        })?;
        let assembly_index = match assemblies
            .iter()
            .position(|(built, _, _)| *built == robot_dimensions)
        {
            Some(index) => index,
            None => {
                let links = assembly::robot(&robot_dimensions)?;
                let summaries: Vec<LinkSummary> =
                    links.iter().map(mass_properties::summarize).collect();
                assemblies.push((robot_dimensions, links, summaries));
                written_glbs.push(None);
                assemblies.len() - 1
            }
        };
        let (_, links, summaries) = &assemblies[assembly_index];
        let robot_config =
            config::load(&robot_root.join(format!("machines/{robot_name}/robot.yaml")))?;
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

    if let Some((reference_dimensions, _, summaries)) = assemblies.first() {
        export::report_bom(summaries);
        export::report_drivetrain(reference_dimensions);
    }
    Ok(())
}
