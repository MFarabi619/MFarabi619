pub mod hardware;
pub mod networking;
pub mod ota;
pub mod sensors;
pub mod services;
pub mod storage;

pub use hardware::{discover_i2c_devices, initialize_i2c_buses};
pub use networking::{NetworkResources, initialize_networking};
pub use ota::validate_ota_slot;
pub use sensors::spawn_sensor_tasks;
pub use services::start_services;
pub use storage::initialize_sd_and_filesystem;
