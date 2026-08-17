use std::error::Error;

use robot_generator_common::{assembly, export, mass_properties, robot_directory};

fn main() -> Result<(), Box<dyn Error>> {
    let links = assembly::mount_motor_and_wheel()?;
    let summaries: Vec<_> = links.iter().map(mass_properties::summarize).collect();
    export::report_bom(&summaries);
    export::write_glb(
        &links,
        &robot_directory().join("assets").join("mount_motor_and_wheel.glb"),
    )
}
