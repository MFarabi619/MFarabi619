#![allow(dead_code)]

use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::thread;

use lazyzephyr_core::{App, tui::popup::{Popup, WaitingProbe}};

#[derive(Debug)]
pub struct ThreadProbe {
    done:  AtomicBool,
    error: Mutex<Option<String>>,
}

impl WaitingProbe for ThreadProbe {
    fn is_done(&self) -> bool { self.done.load(Ordering::Acquire) }
    fn take_error(&self) -> Option<String> {
        self.error.lock().ok().and_then(|mut g| g.take())
    }
}

pub fn with_waiting(app: &mut App, message: impl Into<String>, work: impl FnOnce() -> Result<(), String> + Send + 'static) {
    let probe = Arc::new(ThreadProbe {
        done:  AtomicBool::new(false),
        error: Mutex::new(None),
    });
    let probe_for_thread = Arc::clone(&probe);
    thread::spawn(move || {
        let result = work();
        if let Err(err) = result {
            if let Ok(mut g) = probe_for_thread.error.lock() { *g = Some(err); }
        }
        probe_for_thread.done.store(true, Ordering::Release);
    });
    app.popups.push(Popup::Waiting { message: message.into(), probe });
}
