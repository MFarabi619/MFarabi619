use std::{error::Error, fs};

use cad::{assembly, export, robot_dir, time_it, urdf};
use description::placement::joint_table;

fn main() -> Result<(), Box<dyn Error>> {
    let robot_dir = robot_dir();
    let assets_dir = robot_dir.join("assets");
    fs::create_dir_all(&assets_dir)?;

    let links = assembly::robot()?;
    export::report_geometry_table(links.iter().flat_map(|link| link.solids.iter()));
    export::report_drivetrain();

    export::write_glb(&links, &assets_dir.join("robot.glb"))?;

    let joints = joint_table();
    time_it!("urdf write", urdf::write(&links, &joints, &robot_dir))?;
    println!(
        "wrote {}",
        robot_dir.join("urdf").join("robot.urdf").display()
    );
    Ok(())
}
