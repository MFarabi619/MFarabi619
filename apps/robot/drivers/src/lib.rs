pub mod camera;
pub mod gpio;
pub mod gps;
pub mod i2c;
pub mod led;
pub mod motor;
pub mod pca9685;
pub mod servo;
pub mod spi;
pub mod ssd1306;
pub mod sysfs_pwm;
pub mod webcam;
pub mod ws2812;

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub use camera::{run_camera, CameraProfile, IMX296_GS, ORBBEC_GEMINI_335L, USB_WEBCAM};
pub use gps::run_gps;
pub use webcam::{spawn_webcam_forwarder, WebcamSink};
