use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn boot_write_img_confirmed() -> i32;
    fn boot_is_img_confirmed() -> bool;
}

pub fn is_confirmed() -> bool {
    unsafe { boot_is_img_confirmed() }
}

pub fn confirm() -> Result<(), Errno> {
    unsafe { boot_write_img_confirmed() }.ok()
}
