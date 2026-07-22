use std::error::Error;

use robot_cad::{assembly, export, mass_properties, robot_dir};

fn main() -> Result<(), Box<dyn Error>> {
    let links = assembly::mount_and_motor()?;
    let summaries: Vec<_> = links.iter().map(mass_properties::summarize).collect();
    export::report_bom(&summaries);
    export::write_glb(
        &links,
        &robot_dir().join("assets").join("mount_and_motor.glb"),
    )
}
