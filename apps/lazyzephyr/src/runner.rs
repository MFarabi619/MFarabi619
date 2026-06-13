use std::{
    io::{BufRead, BufReader, Read},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    thread,
};

use lazyzephyr_core::commands::runner::{CommandRunner, StreamStatus, StreamingCommand};

const MAX_LINES: usize = 5000;

pub struct ThreadedRunner;

impl CommandRunner for ThreadedRunner {
    fn spawn(&self, label: String, command: String) -> Arc<dyn StreamingCommand> {
        ThreadedCommand::spawn(label, command)
    }
}

struct ThreadedCommand {
    label:   String,
    command: String,
    state:   Arc<Mutex<State>>,
}

struct State {
    lines:  Vec<String>,
    status: StreamStatus,
}

impl ThreadedCommand {
    fn spawn(label: String, command: String) -> Arc<dyn StreamingCommand> {
        let state = Arc::new(Mutex::new(State { lines: Vec::new(), status: StreamStatus::Running }));

        match Command::new("sh").arg("-c").arg(&command)
            .stdout(Stdio::piped()).stderr(Stdio::piped()).stdin(Stdio::null())
            .spawn()
        {
            Ok(mut child) => {
                if let Some(out) = child.stdout.take() { spawn_reader(out, state.clone()); }
                if let Some(err) = child.stderr.take() { spawn_reader(err, state.clone()); }
                let waiter_state = state.clone();
                thread::spawn(move || {
                    let status = match child.wait() {
                        Ok(s)  => s.code().map(StreamStatus::Exited).unwrap_or(StreamStatus::Killed),
                        Err(_) => StreamStatus::Killed,
                    };
                    waiter_state.lock().unwrap().status = status;
                });
            }
            Err(error) => {
                let mut guard = state.lock().unwrap();
                guard.lines.push(format!("failed to spawn: {error}"));
                guard.status = StreamStatus::Exited(-1);
            }
        }

        Arc::new(Self { label, command, state })
    }
}

fn spawn_reader<R: Read + Send + 'static>(stream: R, state: Arc<Mutex<State>>) {
    thread::spawn(move || {
        let reader = BufReader::new(stream);
        for line in reader.lines().map_while(Result::ok) {
            let mut guard = state.lock().unwrap();
            guard.lines.push(line);
            if guard.lines.len() > MAX_LINES {
                let drop = guard.lines.len() - MAX_LINES;
                guard.lines.drain(..drop);
            }
        }
    });
}

impl StreamingCommand for ThreadedCommand {
    fn label(&self)    -> &str { &self.label }
    fn command(&self)  -> &str { &self.command }
    fn status(&self)   -> StreamStatus { self.state.lock().map(|g| g.status).unwrap_or(StreamStatus::Killed) }
    fn snapshot(&self) -> Vec<String> { self.state.lock().map(|g| g.lines.clone()).unwrap_or_default() }
    fn cancel(&self) {}
}
