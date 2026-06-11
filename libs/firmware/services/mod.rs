#[cfg(CONFIG_MCUMGR_TRANSPORT_UDP)]
pub mod mcumgr {
    use crate::utils::errno::{Errno, IntoResult};
    use zephyr::raw::smp_udp_open;

    pub fn udp_open() -> Result<(), Errno> {
        unsafe { smp_udp_open() }.ok()
    }
}
