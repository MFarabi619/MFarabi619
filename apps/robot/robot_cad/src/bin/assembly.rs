use std::{error::Error, fs};

use robot_cad::{assembly, config, export, mass_properties, robot_dir, time_it, urdf};
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

    let package_dir = robot_dir.join("robot_description");
    let joints = joint_table();
    let robot_config = config::load(&robot_dir.join("robot_config/sample/rover.yaml"))?;
    time_it!(
        "urdf write",
        urdf::write(&links, &joints, &summaries, &robot_config, &package_dir)
    )?;
    println!(
        "wrote {}",
        package_dir.join("urdf").join("robot.urdf").display()
    );
    Ok(())
}
