use crate::utils::errno::{Errno, IntoResult};
use zephyr::raw::{boot_is_img_confirmed, boot_write_img_confirmed};

pub fn is_confirmed() -> bool {
    unsafe { boot_is_img_confirmed() }
}

pub fn confirm() -> Result<(), Errno> {
    unsafe { boot_write_img_confirmed() }.ok()
}
