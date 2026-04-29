#![no_std]
#![feature(impl_trait_in_assoc_type)]

extern crate alloc;

mod led;
mod provisioning;
pub mod sensors;
mod wifi;
mod zephyr_main;

mod defmt_stubs {
    #[unsafe(no_mangle)]
    extern "C" fn _defmt_acquire() {}
    #[unsafe(no_mangle)]
    extern "C" fn _defmt_release() {}
    #[unsafe(no_mangle)]
    extern "C" fn _defmt_write(_: *const u8, _: usize) {}
    #[unsafe(no_mangle)]
    extern "C" fn _defmt_timestamp() -> u64 { 0 }
    #[unsafe(no_mangle)]
    extern "C" fn _defmt_panic() -> ! { panic!("defmt panic") }
}
