use std::io::{self, Write};

use cadrum::{DVec3, Mesh};

use crate::{gltf::smooth_and_group, material::Pbr};

pub fn write_collada<W, F>(mesh: &Mesh, material_lookup: F, writer: &mut W) -> io::Result<()>
where
    W: Write,
    F: Fn([u8; 3]) -> Pbr,
{
    const PHONG_SPECULAR_FLOOR: f64 = 0.2;
    const PHONG_SPECULAR_METALLIC_GAIN: f64 = 0.6;
    const PHONG_SHININESS_MIN: f64 = 1.0;
    const PHONG_SHININESS_RANGE: f64 = 127.0;

    let (positions, normals, color_groups) = smooth_and_group(mesh);

    writeln!(writer, r##"<?xml version="1.0" encoding="utf-8"?>"##)?;
    writeln!(
        writer,
        r##"<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">"##
    )?;
    writeln!(
        writer,
        r##"  <asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>"##
    )?;

    writeln!(writer, "  <library_effects>")?;
    for (index, (rgb, _)) in color_groups.iter().enumerate() {
        let props = material_lookup(*rgb);
        let [red, green, blue] = rgb.map(|channel| channel as f64 / 255.0);
        let specular = PHONG_SPECULAR_FLOOR + PHONG_SPECULAR_METALLIC_GAIN * props.metallic as f64;
        let shininess =
            PHONG_SHININESS_MIN + PHONG_SHININESS_RANGE * (1.0 - props.roughness as f64);
        writeln!(
            writer,
            r##"    <effect id="effect{index}"><profile_COMMON><technique sid="common"><phong>"##
        )?;
        writeln!(
            writer,
            "      <diffuse><color>{red:.4} {green:.4} {blue:.4} 1</color></diffuse>"
        )?;
        writeln!(
            writer,
            "      <specular><color>{specular:.4} {specular:.4} {specular:.4} 1</color></specular>"
        )?;
        writeln!(
            writer,
            "      <shininess><float>{shininess:.1}</float></shininess>"
        )?;
        writeln!(writer, "    </phong></technique></profile_COMMON></effect>")?;
    }
    writeln!(writer, "  </library_effects>")?;

    writeln!(writer, "  <library_materials>")?;
    for index in 0..color_groups.len() {
        writeln!(
            writer,
            r##"    <material id="material{index}"><instance_effect url="#effect{index}"/></material>"##
        )?;
    }
    writeln!(writer, "  </library_materials>")?;

    writeln!(writer, "  <library_geometries>")?;
    writeln!(writer, r##"    <geometry id="geometry"><mesh>"##)?;
    write_source(writer, "positions", &positions)?;
    write_source(writer, "normals", &normals)?;
    writeln!(
        writer,
        r##"      <vertices id="vertices"><input semantic="POSITION" source="#positions"/></vertices>"##
    )?;
    for (index, (_, triangle_indices)) in color_groups.iter().enumerate() {
        writeln!(
            writer,
            r##"      <triangles material="material{index}" count="{}">"##,
            triangle_indices.len() / 3
        )?;
        writeln!(
            writer,
            r##"        <input semantic="VERTEX" source="#vertices" offset="0"/>"##
        )?;
        writeln!(
            writer,
            r##"        <input semantic="NORMAL" source="#normals" offset="0"/>"##
        )?;
        write!(writer, "        <p>")?;
        for (position, vertex_index) in triangle_indices.iter().enumerate() {
            if position > 0 {
                write!(writer, " ")?;
            }
            write!(writer, "{vertex_index}")?;
        }
        writeln!(writer, "</p>")?;
        writeln!(writer, "      </triangles>")?;
    }
    writeln!(writer, "    </mesh></geometry>")?;
    writeln!(writer, "  </library_geometries>")?;

    writeln!(writer, "  <library_visual_scenes>")?;
    writeln!(writer, r##"    <visual_scene id="scene">"##)?;
    writeln!(
        writer,
        r##"      <node id="node"><instance_geometry url="#geometry"><bind_material><technique_common>"##
    )?;
    for index in 0..color_groups.len() {
        writeln!(
            writer,
            r##"        <instance_material symbol="material{index}" target="#material{index}"/>"##
        )?;
    }
    writeln!(
        writer,
        "      </technique_common></bind_material></instance_geometry></node>"
    )?;
    writeln!(writer, "    </visual_scene>")?;
    writeln!(writer, "  </library_visual_scenes>")?;
    writeln!(
        writer,
        r##"  <scene><instance_visual_scene url="#scene"/></scene>"##
    )?;
    writeln!(writer, "</COLLADA>")?;
    Ok(())
}

fn write_source<W: Write>(writer: &mut W, id: &str, vectors: &[DVec3]) -> io::Result<()> {
    writeln!(writer, r##"      <source id="{id}">"##)?;
    write!(
        writer,
        r##"        <float_array id="{id}-array" count="{}">"##,
        vectors.len() * 3
    )?;
    for (index, vector) in vectors.iter().enumerate() {
        if index > 0 {
            write!(writer, " ")?;
        }
        write!(
            writer,
            "{:.6} {:.6} {:.6}",
            finite(vector.x),
            finite(vector.y),
            finite(vector.z)
        )?;
    }
    writeln!(writer, "</float_array>")?;
    writeln!(
        writer,
        r##"        <technique_common><accessor source="#{id}-array" count="{}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common>"##,
        vectors.len()
    )?;
    writeln!(writer, "      </source>")?;
    Ok(())
}

fn finite(value: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        0.0
    }
}
