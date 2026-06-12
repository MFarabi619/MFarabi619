use alloc::{string::String, vec::Vec};

#[derive(Debug, Clone, Default)]
pub struct ElfInfo {
    pub path:    String,
    pub headers: Vec<(String, String)>,
    pub error:   Option<String>,
}

impl ElfInfo {
    pub fn loaded(&self) -> bool {
        !self.headers.is_empty() && self.error.is_none()
    }
}
