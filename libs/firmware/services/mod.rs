#[cfg(CONFIG_MCUMGR_TRANSPORT_UDP)]
pub mod mcumgr {
    use crate::utils::errno::{Errno, IntoResult};

    extern "C" {
        fn smp_udp_open() -> i32;
    }

    pub fn udp_open() -> Result<(), Errno> {
        unsafe { smp_udp_open() }.ok()
    }
}
