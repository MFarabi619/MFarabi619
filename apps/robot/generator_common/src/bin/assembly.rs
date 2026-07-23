use std::{error::Error, fs};

use robot_generator_common::{assembly, config, export, mass_properties, robot_dir, time_it, urdf};
use robot_description::placement::joint_table;

fn main() -> Result<(), Box<dyn Error>> {
    let robot_dir = robot_dir();
    let assets_dir = robot_dir.join("assets");
    fs::create_dir_all(&assets_dir)?;

    let links = assembly::robot()?;
    let summaries: Vec<_> = links.iter().map(mass_properties::summarize).collect();
    export::report_bom(&summaries);
    export::report_drivetrain();

    export::write_glb(&links, &assets_dir.join("robot.glb"))?;

    let package_dir = robot_dir.join("description");
    let joints = joint_table();
    let mut robot_names: Vec<_> = fs::read_dir(robot_dir.join("config/robots"))?
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.path().join("robot.yaml").is_file())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    robot_names.sort();
    for robot_name in &robot_names {
        let robot_config =
            config::load(&robot_dir.join(format!("config/robots/{robot_name}/robot.yaml")))?;
        time_it!(
            "urdf write",
            urdf::write(&links, &joints, &summaries, &robot_config, robot_name, &package_dir)
        )?;
        println!(
            "wrote {}",
            package_dir.join("urdf").join(robot_name).join("robot.urdf").display()
        );
    }

    let drivetrain = robot_dir.join("control/config/drivetrain.generated.yaml");
    fs::write(&drivetrain, urdf::drivetrain_params())?;
    println!("wrote {}", drivetrain.display());
    Ok(())
}
