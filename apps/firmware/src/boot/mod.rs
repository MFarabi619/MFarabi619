use zephyr::error::to_result_void;
use zephyr::raw::{boot_is_img_confirmed, boot_write_img_confirmed};

pub fn is_confirmed() -> bool {
    unsafe { boot_is_img_confirmed() }
}

pub fn confirm() -> zephyr::Result<()> {
    to_result_void(unsafe { boot_write_img_confirmed() })
}
