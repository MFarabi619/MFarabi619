use std::sync::Mutex;

use lazyzephyr_core::tui::matcher::Matcher;
use nucleo_matcher::{Config, Matcher as Nucleo, Utf32Str};

pub struct NucleoMatcher {
    inner: Mutex<Nucleo>,
}

impl NucleoMatcher {
    pub fn new() -> Self {
        Self { inner: Mutex::new(Nucleo::new(Config::DEFAULT)) }
    }
}

impl Default for NucleoMatcher {
    fn default() -> Self { Self::new() }
}

impl Matcher for NucleoMatcher {
    fn match_score(&self, haystack: &str, needle: &str) -> Option<i64> {
        if needle.is_empty() { return Some(0); }
        let mut h_buf = Vec::new();
        let mut n_buf = Vec::new();
        let h = Utf32Str::new(haystack, &mut h_buf);
        let n = Utf32Str::new(needle, &mut n_buf);
        let mut guard = self.inner.lock().ok()?;
        guard.fuzzy_match(h, n).map(|s| s as i64)
    }

    fn highlight_indices(&self, haystack: &str, needle: &str) -> Option<Vec<usize>> {
        if needle.is_empty() { return None; }
        let mut h_buf = Vec::new();
        let mut n_buf = Vec::new();
        let h = Utf32Str::new(haystack, &mut h_buf);
        let n = Utf32Str::new(needle, &mut n_buf);
        let mut guard = self.inner.lock().ok()?;
        let mut indices = Vec::new();
        guard.fuzzy_indices(h, n, &mut indices)?;
        Some(indices.into_iter().map(|i| i as usize).collect())
    }
}
