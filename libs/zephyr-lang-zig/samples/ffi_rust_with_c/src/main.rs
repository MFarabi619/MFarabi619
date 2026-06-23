use rust_ffi::compute_stats;

const SAMPLE_COUNT: usize = 16;
const CALIBRATION_OFFSET: u32 = 100;

fn main() {
    let samples: [u32; SAMPLE_COUNT] =
        std::array::from_fn(|index| CALIBRATION_OFFSET + index as u32);
    let stats = compute_stats(&samples);
    println!(
        "rust: min={} mean={} max={} crc32=0x{:08x}",
        stats.min, stats.mean, stats.max, stats.crc32,
    );
}
