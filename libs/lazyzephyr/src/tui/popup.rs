use alloc::{string::String, sync::Arc};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToastKind {
    Info,
    Success,
    Error,
}

pub trait WaitingProbe: Send + Sync + core::fmt::Debug {
    fn is_done(&self)    -> bool;
    fn take_error(&self) -> Option<String>;
}

#[derive(Debug, Clone)]
pub enum Popup {
    Help,
    Menu    { selection: usize },
    Confirm { title: &'static str, message: String, on_confirm: fn(&mut crate::tui::state::App) },
    Alert   { title: &'static str, message: String },
    Prompt  { title: &'static str, value: String, cursor: usize, on_submit: fn(&mut crate::tui::state::App, &str) },
    Toast   { message: String, kind: ToastKind, expires_at: u32 },
    Waiting { message: String, probe: Arc<dyn WaitingProbe> },
}
