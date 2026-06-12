use alloc::{boxed::Box, string::String, sync::Arc};

#[derive(Debug, Clone, Default)]
pub struct EchoSample {
    pub latency_ms: u32,
    pub response:   String,
    pub at_tick:    u32,
}

#[derive(Debug, Clone, Default)]
pub struct EchoState {
    pub last:       Option<EchoSample>,
    pub last_error: Option<String>,
    pub busy:       bool,
}

pub trait McumgrService: Send + Sync {
    fn echo_state(&self) -> EchoState;
    fn ping_async(&self, at_tick: u32);
}

pub struct NoopMcumgr;

impl McumgrService for NoopMcumgr {
    fn echo_state(&self) -> EchoState {
        EchoState { last: None, last_error: Some("mcumgr not configured".into()), busy: false }
    }
    fn ping_async(&self, _at_tick: u32) {}
}

pub fn noop_arc() -> Arc<dyn McumgrService> { Arc::new(NoopMcumgr) }

#[allow(dead_code)]
pub fn noop_box() -> Box<dyn McumgrService> { Box::new(NoopMcumgr) }
