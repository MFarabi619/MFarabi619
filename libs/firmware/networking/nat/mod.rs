use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn nat_initialize() -> i32;
}

pub fn initialize() -> Result<(), Errno> {
    unsafe { nat_initialize() }.ok()
}
