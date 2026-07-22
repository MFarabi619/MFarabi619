use std::path::{Path, PathBuf};

use cadrum::{DVec3, Solid};
pub use robot_description::link::{Joint, JointType, LinkId};

pub mod assembly;
pub mod collada;
pub mod config;
pub mod export;
pub mod gltf;
pub mod mass_properties;
pub mod material;
pub mod urdf;

pub struct Link {
    pub id: LinkId,
    pub origin_world: DVec3,
    pub solids: Vec<Solid>,
}

pub fn robot_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("cad crate lives under the robot package")
        .to_path_buf()
}

pub fn asset(name: &str) -> PathBuf {
    robot_dir().join("assets").join(name)
}

#[macro_export]
macro_rules! time_it {
    ($name:expr, $body:expr) => {{
        let start = ::std::time::Instant::now();
        let result = $body;
        eprintln!(
            "[cad] {:<24} {:>7.2}s",
            $name,
            start.elapsed().as_secs_f64()
        );
        result
    }};
}
