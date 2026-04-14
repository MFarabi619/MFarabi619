//! Compile-time feature flags — on/off switches for subsystems.

pub mod telnet {
    pub const ENABLED: bool = false;
}

pub mod provisioning {
    pub const ENABLED: bool = false;
}

pub mod smtp {
    pub const ENABLED: bool = false;
}
