use std::error::Error;

use robot_description::{assembly, export, mass_properties, robot_root};

fn main() -> Result<(), Box<dyn Error>> {
    let links = assembly::mount_and_motor()?;
    let summaries: Vec<_> = links.iter().map(mass_properties::summarize).collect();
    export::report_bom(&summaries);
    export::write_glb(
        &links,
        &robot_root()
            .join("assets")
            .join("meshes")
            .join("mount_and_motor.glb"),
    )
}
