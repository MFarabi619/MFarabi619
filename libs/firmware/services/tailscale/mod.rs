use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn tailscaleStart() -> i32;
}

pub fn start() -> Result<(), Errno> {
    unsafe { tailscaleStart() }.ok()
}
