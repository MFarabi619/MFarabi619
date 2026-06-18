#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Thresholds {
    pub p1: f32,
    pub p2: f32,
    pub p3: f32,
}

impl Default for Thresholds {
    fn default() -> Self {
        Self { p1: 0.95, p2: 0.95, p3: 20.0 }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Stats {
    pub green: u32,
    pub total: u32,
}

impl Stats {
    pub fn fgcc(&self) -> f32 {
        if self.total == 0 { 0.0 } else { self.green as f32 / self.total as f32 }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Preset {
    pub name: &'static str,
    pub thresholds: Thresholds,
}

pub const PRESETS: &[Preset] = &[
    Preset { name: "Default",        thresholds: Thresholds { p1: 0.95, p2: 0.95, p3: 20.0 } },
    Preset { name: "Corn",           thresholds: Thresholds { p1: 0.97, p2: 0.97, p3: 20.0 } },
    Preset { name: "Forage sorghum", thresholds: Thresholds { p1: 0.97, p2: 0.97, p3: 20.0 } },
    Preset { name: "Turf",           thresholds: Thresholds { p1: 0.99, p2: 0.99, p3: 20.0 } },
    Preset { name: "Switchgrass",    thresholds: Thresholds { p1: 1.10, p2: 1.10, p3: 20.0 } },
];

pub fn classify_in_place(rgba: &mut [u8], thr: &Thresholds) -> Stats {
    let mut green: u32 = 0;
    let mut total: u32 = 0;
    for pixel in rgba.chunks_exact_mut(4) {
        total += 1;
        let red = pixel[0] as f32;
        let g = pixel[1] as f32;
        let blue = pixel[2] as f32;
        let is_green = g > 0.0
            && (red / g) < thr.p1
            && (blue / g) < thr.p2
            && (2.0 * g - red - blue) > thr.p3;
        let value: u8 = if is_green { 255 } else { 0 };
        if is_green { green += 1; }
        pixel[0] = value;
        pixel[1] = value;
        pixel[2] = value;
        pixel[3] = 255;
    }
    Stats { green, total }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pure_green_classifies_green() {
        let mut buffer = [0, 200, 0, 255];
        let stats = classify_in_place(&mut buffer, &Thresholds::default());
        assert_eq!(stats.green, 1);
        assert_eq!(buffer, [255, 255, 255, 255]);
    }

    #[test]
    fn pure_red_classifies_not_green() {
        let mut buffer = [200, 0, 0, 255];
        let stats = classify_in_place(&mut buffer, &Thresholds::default());
        assert_eq!(stats.green, 0);
        assert_eq!(buffer, [0, 0, 0, 255]);
    }

    #[test]
    fn excess_green_index_filters_dark() {
        let mut buffer = [10, 11, 10, 255];
        let stats = classify_in_place(&mut buffer, &Thresholds::default());
        assert_eq!(stats.green, 0);
    }
}
