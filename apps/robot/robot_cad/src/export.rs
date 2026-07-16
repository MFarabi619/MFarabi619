use std::{error::Error, fs::File, path::Path};

#[allow(unused_imports)]
use cadrum::SceneOption;
use cadrum::{DVec3, Solid, Tessellation};
use comfy_table::{modifiers, presets::UTF8_FULL, Attribute, Cell, Color, Table};

use crate::{
    gltf::write_shaded_glb, mass_properties::LinkSummary, material::Material, time_it, Link,
};

fn to_gltf_y_up(solid: Solid) -> Solid {
    solid.align_z(DVec3::Y, DVec3::X)
}

pub const TESSELLATION: Tessellation = Tessellation {
    deflection_linear: 0.01,
    deflection_angular: 0.05,
    relative_linear: true,
    is_parallel: true,
};

pub fn write_glb(links: &[Link], glb_path: &Path) -> Result<(), Box<dyn Error>> {
    let viewer_solids: Vec<Solid> = time_it!(
        "to_gltf_y_up",
        links
            .iter()
            .flat_map(|link| link.solids.iter().cloned())
            .map(to_gltf_y_up)
            .collect()
    );
    let mesh = time_it!("tessellation", Solid::mesh(&viewer_solids, TESSELLATION))?;
    time_it!(
        "gltf write",
        write_shaded_glb(&mesh, Material::pbr_for_rgb, &mut File::create(glb_path)?)
    )?;
    println!("wrote {}", glb_path.display());

    // PNG render is single-threaded via tiny-skia and takes far longer than tessellation on this
    // model (15+ min single-view at 1024²). Un-comment when a still is genuinely needed.
    // time_it!(
    //     "png write",
    //     mesh.scene(SceneOption { shading: true, hidden_edges: false, ..SceneOption::default() })
    //         .write_png([1024, 1024], &mut File::create(&png_path)?)
    // )?;

    Ok(())
}

fn styled_table() -> Table {
    let mut table = Table::new();
    table
        .load_preset(UTF8_FULL)
        .apply_modifier(modifiers::UTF8_ROUND_CORNERS);
    table
}

fn header(labels: impl IntoIterator<Item = (&'static str, Color)>) -> Vec<Cell> {
    labels
        .into_iter()
        .map(|(label, color)| Cell::new(label).fg(color).add_attribute(Attribute::Bold))
        .collect()
}

fn number(value: String, color: Color) -> Cell {
    Cell::new(value).fg(color)
}

pub fn report_drivetrain() {
    use robot_description::{
        datums::WHEEL_TREAD_DIAMETER_MM,
        placement::{ground_z, wheel_origin, Corner},
    };
    let front = wheel_origin(Corner::FrontLeft);
    let rear = wheel_origin(Corner::RearLeft);
    let mut table = styled_table();
    table.set_header(header([("drivetrain", Color::Cyan), ("mm", Color::Yellow)]));
    for (label, value) in [
        ("track", 2.0 * front.y),
        ("front axle x", front.x),
        ("rear axle x", rear.x),
        ("tread radius", WHEEL_TREAD_DIAMETER_MM / 2.0),
        ("ground clearance", ground_z()),
    ] {
        table.add_row(vec![
            Cell::new(label).fg(Color::Cyan),
            number(format!("{value:.1}"), Color::Yellow),
        ]);
    }
    println!("{table}");
}

pub fn report_bom(summaries: &[LinkSummary]) {
    let columns = [
        ("link", Color::Blue),
        ("parts", Color::Green),
        ("material", Color::Cyan),
        ("mass (kg)", Color::Yellow),
    ];
    let mut table = styled_table();
    table.set_header(header(columns));

    let mut ordered: Vec<&LinkSummary> = summaries.iter().collect();
    ordered.sort_by(|left, right| right.mass.total_cmp(&left.mass));

    let mut total_mass = 0.0;
    for summary in ordered {
        total_mass += summary.mass;
        table.add_row(vec![
            Cell::new(summary.id.urdf_name()).fg(columns[0].1),
            number(summary.parts.to_string(), columns[1].1),
            Cell::new(summary.material.map_or("?", Material::label)).fg(columns[2].1),
            number(format!("{:.3}", summary.mass), columns[3].1),
        ]);
    }
    table.add_row(vec![
        Cell::new("total").add_attribute(Attribute::Bold),
        Cell::new(""),
        Cell::new(""),
        number(format!("{total_mass:.3}"), columns[3].1).add_attribute(Attribute::Bold),
    ]);
    println!("{table}");
}
