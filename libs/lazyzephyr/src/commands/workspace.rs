use alloc::{string::String, vec::Vec};

#[derive(Debug, Default, Clone)]
pub struct WestWorkspace {
    pub config:   Vec<ConfigEntry>,
    pub projects: Vec<WestProject>,
    pub boards:   Vec<WestBoard>,
}

#[derive(Debug, Clone)]
pub struct ConfigEntry {
    pub key:   String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct WestProject {
    pub name:     String,
    pub path:     String,
    pub revision: String,
    pub url:      String,
}

#[derive(Debug, Clone)]
pub struct WestBoard {
    pub name:      String,
    pub full_name: String,
    pub vendor:    String,
}
