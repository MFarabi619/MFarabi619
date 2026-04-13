use esp_hal::rng::Rng;

/// ESP32-S3 hardware RNG wrapped to satisfy `rand::CryptoRng`.
/// The hardware RNG produces true random numbers from thermal noise.
pub struct CryptoRng(pub Rng);

impl rand::RngCore for CryptoRng {
    fn next_u32(&mut self) -> u32 {
        self.0.random()
    }

    fn next_u64(&mut self) -> u64 {
        (u64::from(self.0.random()) << 32) | u64::from(self.0.random())
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        for chunk in dest.chunks_mut(4) {
            let r = self.0.random().to_le_bytes();
            chunk.copy_from_slice(&r[..chunk.len()]);
        }
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand::Error> {
        self.fill_bytes(dest);
        Ok(())
    }
}

impl rand::CryptoRng for CryptoRng {}
