use alloc::{boxed::Box, vec::Vec};

pub trait Matcher: Send + Sync {
    fn match_score(&self, haystack: &str, needle: &str) -> Option<i64>;

    fn highlight_indices(&self, _haystack: &str, _needle: &str) -> Option<Vec<usize>> { None }
}

pub struct SubstringMatcher;

impl Matcher for SubstringMatcher {
    fn match_score(&self, haystack: &str, needle: &str) -> Option<i64> {
        if needle.is_empty() { return Some(0); }
        let h = haystack.to_lowercase();
        let n = needle.to_lowercase();
        h.find(n.as_str()).map(|pos| 1_000_000 - pos as i64)
    }

    fn highlight_indices(&self, haystack: &str, needle: &str) -> Option<Vec<usize>> {
        if needle.is_empty() { return None; }
        let h = haystack.to_lowercase();
        let n = needle.to_lowercase();
        let byte_pos = h.find(n.as_str())?;
        let needle_len = n.chars().count();
        let char_start = h[..byte_pos].chars().count();
        Some((char_start..char_start + needle_len).collect())
    }
}

pub fn boxed_default() -> Box<dyn Matcher> { Box::new(SubstringMatcher) }
