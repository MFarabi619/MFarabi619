use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn natInitialize() -> i32;
}

pub fn initialize() -> Result<(), Errno> {
    unsafe { natInitialize() }.ok()
}
