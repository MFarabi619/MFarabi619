use std::path::PathBuf;

pub mod onnx;
pub mod palm;

pub fn models_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("models")
}
