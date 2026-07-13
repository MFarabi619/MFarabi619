use std::error::Error;

use cad::{assembly, export, robot_dir};

fn main() -> Result<(), Box<dyn Error>> {
    let links = assembly::mount_motor_and_wheel()?;
    export::report_geometry_table(links.iter().flat_map(|link| link.solids.iter()));
    export::write_glb(
        &links,
        &robot_dir().join("assets").join("mount_motor_and_wheel.glb"),
    )
}
