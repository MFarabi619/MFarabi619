use std::error::Error;

use robot_cad::{assembly, export, mass_properties, robot_dir};

fn main() -> Result<(), Box<dyn Error>> {
    let links = assembly::wheel()?;
    let summaries: Vec<_> = links.iter().map(mass_properties::summarize).collect();
    export::report_bom(&summaries);
    export::write_glb(&links, &robot_dir().join("assets").join("wheel.glb"))
}
