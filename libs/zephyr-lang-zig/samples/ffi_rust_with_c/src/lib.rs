#![cfg_attr(target_os = "none", no_std)]

use core::slice;

use crc::{Crc, CRC_32_ISO_HDLC};
use heapless::Vec;

#[cfg(target_os = "none")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[repr(C)]
pub struct SensorStats {
    pub min: u32,
    pub mean: u32,
    pub max: u32,
    pub crc32: u32,
}

const MAX_SAMPLES: usize = 64;
const CRC32_HASHER: Crc<u32> = Crc::<u32>::new(&CRC_32_ISO_HDLC);

pub fn compute_stats(samples: &[u32]) -> SensorStats {
    if samples.is_empty() {
        return SensorStats { min: 0, mean: 0, max: 0, crc32: 0 };
    }

    let mut bounded: Vec<u32, MAX_SAMPLES> = Vec::new();
    for &sample in samples {
        if bounded.push(sample).is_err() {
            break;
        }
    }

    let min = *bounded.iter().min().unwrap();
    let max = *bounded.iter().max().unwrap();
    let sum: u64 = bounded.iter().map(|&sample| sample as u64).sum();
    let mean = (sum / bounded.len() as u64) as u32;

    let mut digest = CRC32_HASHER.digest();
    for &sample in &bounded {
        digest.update(&sample.to_le_bytes());
    }
    let crc32 = digest.finalize();

    SensorStats { min, mean, max, crc32 }
}

#[no_mangle]
pub extern "C" fn rust_compute_stats(samples: *const u32, len: usize) -> SensorStats {
    if samples.is_null() || len == 0 {
        return SensorStats { min: 0, mean: 0, max: 0, crc32: 0 };
    }
    // SAFETY: caller guarantees `samples` points to `len` contiguous u32 values.
    let slice = unsafe { slice::from_raw_parts(samples, len) };
    compute_stats(slice)
}
