use bt_hci::controller::ExternalController;
use trouble_host::prelude::{DefaultPacketPool, HostResources};

pub const CONNECTIONS_MAX: usize = 1;
pub const L2CAP_CHANNELS_MAX: usize = 1;

pub type BleHostResources = HostResources<DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX>;

pub fn new_ble_controller<T>(transport: T) -> ExternalController<T, 1> {
    ExternalController::<_, 1>::new(transport)
}

pub fn new_ble_resources() -> BleHostResources {
    HostResources::new()
}
