pub mod camera;
pub mod gps;
pub mod webcam;

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub use camera::{run_camera, CameraProfile, IMX296_GS, ORBBEC_GEMINI_335L, USB_WEBCAM};
pub use gps::run_gps;
pub use webcam::{spawn_webcam_forwarder, WebcamSink};
