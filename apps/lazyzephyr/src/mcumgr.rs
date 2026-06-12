use std::{
    error::Error,
    net::SocketAddr,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use lazyzephyr_core::commands::mcumgr::{EchoSample, EchoState, McumgrService};
use mcumgr_toolkit::MCUmgrClient;

pub struct UdpMcumgr {
    client: Arc<MCUmgrClient>,
    state:  Arc<Mutex<EchoState>>,
}

impl UdpMcumgr {
    pub fn connect(addr: SocketAddr, timeout: Duration) -> Result<Self, String> {
        let client = MCUmgrClient::new_from_udp(addr, timeout).map_err(|e| e.to_string())?;
        Ok(Self { client: Arc::new(client), state: Arc::new(Mutex::new(EchoState::default())) })
    }
}

impl McumgrService for UdpMcumgr {
    fn echo_state(&self) -> EchoState {
        self.state.lock().map(|g| g.clone()).unwrap_or_default()
    }

    fn ping_async(&self, at_tick: u32) {
        {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(_) => return,
            };
            if g.busy { return; }
            g.busy = true;
        }
        let client = Arc::clone(&self.client);
        let state  = Arc::clone(&self.state);
        thread::spawn(move || {
            let started = Instant::now();
            let result  = client.os_echo("ping");
            let elapsed = started.elapsed().as_millis() as u32;
            let mut g = match state.lock() { Ok(g) => g, Err(_) => return };
            match result {
                Ok(response) => {
                    g.last = Some(EchoSample { latency_ms: elapsed, response, at_tick });
                    g.last_error = None;
                }
                Err(err) => {
                    g.last_error = Some(format_error_chain(&err));
                }
            }
            g.busy = false;
        });
    }
}

fn format_error_chain(err: &(dyn Error + 'static)) -> String {
    let mut out = err.to_string();
    let mut cur: Option<&dyn Error> = err.source();
    while let Some(e) = cur {
        out.push_str(": ");
        out.push_str(&e.to_string());
        cur = e.source();
    }
    out
}
