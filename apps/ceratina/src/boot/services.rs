use embassy_executor::Spawner;
use embassy_net::Stack;

use crate::{networking, programs, services};

pub fn start_services(
    spawner: &Spawner,
    stack: Stack<'static>,
    flash: esp_storage::FlashStorage<'static>,
) {
    networking::sntp::spawn(spawner, stack);
    services::http::spawn(spawner, stack);
    services::ota::spawn(spawner, stack, flash);
    programs::shell::spawn(spawner, stack);
}
