use alloc::{boxed::Box, string::String, sync::Arc, vec::Vec};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamStatus {
    Running,
    Exited(i32),
    Killed,
}

pub trait StreamingCommand: Send + Sync {
    fn label(&self) -> &str;
    fn command(&self) -> &str;
    fn status(&self) -> StreamStatus;
    fn snapshot(&self) -> Vec<String>;
    fn cancel(&self);
}

pub trait CommandRunner: Send + Sync {
    fn spawn(&self, label: String, command: String) -> Arc<dyn StreamingCommand>;
}

pub struct NoopRunner;

impl CommandRunner for NoopRunner {
    fn spawn(&self, label: String, command: String) -> Arc<dyn StreamingCommand> {
        Arc::new(NoopStreaming { label, command })
    }
}

struct NoopStreaming {
    label:   String,
    command: String,
}

impl StreamingCommand for NoopStreaming {
    fn label(&self)   -> &str { &self.label }
    fn command(&self) -> &str { &self.command }
    fn status(&self)  -> StreamStatus { StreamStatus::Exited(0) }
    fn snapshot(&self) -> Vec<String> { Vec::new() }
    fn cancel(&self) {}
}

pub fn noop_box() -> Box<dyn CommandRunner> { Box::new(NoopRunner) }
