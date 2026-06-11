use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn boot_write_img_confirmed() -> i32;
}

pub fn confirm() -> Result<(), Errno> {
    unsafe { boot_write_img_confirmed() }.ok()
}
