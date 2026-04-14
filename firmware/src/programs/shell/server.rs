use core::fmt::Write;

use alloc::string::String as AllocString;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Stack, tcp::TcpSocket};
use embassy_time::{Duration, Timer};
use esp_hal::rng::Rng;

use crate::hardware::crypto::CryptoRng;
use crate::services::{identity, ssh::{AuthMethod, Behavior, Request, SecretKey, Transport}};

use super::{
    build_motd, build_prompt, dispatch, load_history, save_history, set_terminal_width,
    CTRL_L, CTRL_N, CTRL_P, CTRL_U, CTRL_W,
};

const SSH_PORT: u16 = crate::config::ssh::PORT;
const RX_BUF_SIZE: usize = crate::config::ssh::RX_BUF_SIZE;
const TX_BUF_SIZE: usize = crate::config::ssh::TX_BUF_SIZE;

#[derive(Clone, Copy)]
pub struct TermSize {
    pub width: u32,
    pub height: u32,
}

struct SshBehavior<'a> {
    socket: TcpSocket<'a>,
    rng: CryptoRng,
    host_key: SecretKey,
    term_size: &'a core::cell::Cell<TermSize>,
}

impl<'a> Behavior for SshBehavior<'a> {
    type Stream = TcpSocket<'a>;

    fn stream(&mut self) -> &mut Self::Stream {
        &mut self.socket
    }

    type Random = CryptoRng;

    fn random(&mut self) -> &mut Self::Random {
        &mut self.rng
    }

    fn host_secret_key(&self) -> &SecretKey {
        &self.host_key
    }

    type User = ();

    fn allow_user(&mut self, username: &str, auth_method: &AuthMethod) -> Option<()> {
        if username == identity::ssh_user() && matches!(auth_method, AuthMethod::None) {
            Some(())
        } else {
            None
        }
    }

    fn allow_shell(&self) -> bool {
        true
    }

    fn on_pty_request(&mut self, width: u32, height: u32) {
        self.term_size.set(TermSize { width, height });
    }

    type Command = ();

    fn parse_command(&mut self, _: &str) {}
}

async fn redraw_line<T: Behavior>(
    channel: &mut crate::services::ssh::Channel<'_, '_, T>,
    terminal: &crate::services::ssh::terminal::Terminal<256>,
) {
    let _ = channel.write_all_stdout(b"\r\x1b[K").await;
    let mut prefix = AllocString::new();
    let _ = write!(
        prefix,
        "{}{}{} ",
        super::prompt::theme::FRAME_COLOR,
        super::prompt::theme::FRAME_BOT_LEFT,
        super::prompt::theme::RESET
    );
    let _ = channel.write_all_stdout(prefix.as_bytes()).await;

    if let Ok(buf) = terminal.buffer_str() {
        let _ = channel.write_all_stdout(buf.as_bytes()).await;
        let cursor = terminal.cursor_position();
        let buf_len = buf.len();
        if cursor < buf_len {
            let mut back = AllocString::new();
            let _ = write!(back, "\x1b[{}D", buf_len - cursor);
            let _ = channel.write_all_stdout(back.as_bytes()).await;
        }
    }
}

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>) {
    info!("Microshell (SSH) listening on port {}", SSH_PORT);

    loop {
        static mut RX_BUFFER: [u8; RX_BUF_SIZE] = [0; RX_BUF_SIZE];
        static mut TX_BUFFER: [u8; TX_BUF_SIZE] = [0; TX_BUF_SIZE];

        let socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFFER),
                &mut *core::ptr::addr_of_mut!(TX_BUFFER),
            )
        };

        let term_size = core::cell::Cell::new(TermSize { width: 80, height: 24 });

        let mut behavior = SshBehavior {
            socket,
            rng: CryptoRng(Rng::new()),
            host_key: SecretKey::Ed25519 {
                secret_key: identity::signing_key(),
            },
            term_size: &term_size,
        };

        if let Err(error) = behavior.socket.accept(SSH_PORT).await {
            info!("SSH accept failed: {:?}", error);
            Timer::after(Duration::from_millis(250)).await;
            continue;
        }

        let remote_str = behavior
            .socket
            .remote_endpoint()
            .map(|endpoint| {
                let mut s = AllocString::new();
                let _ = write!(s, "{}", endpoint);
                s
            })
            .unwrap_or_else(|| AllocString::from("unknown"));
        info!("SSH client connected from {}", remote_str.as_str());
        behavior.socket.set_timeout(Some(Duration::from_secs(300)));

        let mut packet_buffer = [0u8; 4096];
        let mut transport = Transport::new(&mut packet_buffer, behavior);

        match transport.accept().await {
            Ok(mut channel) => {
                info!("SSH channel opened");

                match channel.request() {
                    Request::Shell => {
                        let term_size = term_size.get();
                        info!("Terminal size: {}x{}", term_size.width, term_size.height);
                        set_terminal_width(term_size.width);

                        let _ = channel.write_all_stdout(b"\x1b[2J\x1b[H").await;
                        let motd = build_motd(remote_str.as_str());
                        let _ = channel.write_all_stdout(motd.as_bytes()).await;

                        let mut cwd = identity::home_dir();

                        if let Ok(mshrc) =
                            crate::filesystems::sd::read_file_at::<1024>(cwd.as_str(), ".MSHRC")
                        {
                            if let Ok(text) = core::str::from_utf8(mshrc.as_slice()) {
                                for line in text.lines() {
                                    let line = line.trim();
                                    if line.is_empty() || line.starts_with('#') {
                                        continue;
                                    }
                                    let (output, _) = dispatch(line, &mut cwd);
                                    if !output.is_empty() {
                                        let _ = channel.write_all_stdout(output.as_bytes()).await;
                                    }
                                }
                            }
                        }

                        let prompt_str = build_prompt(&cwd);
                        let _ = channel.write_all_stdout(prompt_str.as_bytes()).await;

                        use crate::services::ssh::history::{History, HistoryConfig};
                        use crate::services::ssh::terminal::{Terminal, TerminalConfig, TerminalEvent};

                        let mut terminal = Terminal::<256>::new(TerminalConfig {
                            buffer_size: 256,
                            prompt: "",
                            echo: true,
                            ansi_enabled: true,
                        });

                        let mut history = History::<256>::new(HistoryConfig {
                            max_entries: 16,
                            deduplicate: true,
                        });
                        load_history(&mut history);

                        loop {
                            let mut byte_buf = [0u8; 1];
                            match channel.read_exact_stdin(&mut byte_buf).await {
                                Ok(0) => break,
                                Err(_) => break,
                                Ok(_) => {}
                            }

                            let byte = byte_buf[0];

                            if byte == CTRL_L {
                                let _ = channel.write_all_stdout(b"\x1b[2J\x1b[H").await;
                                terminal.clear_buffer();
                                let prompt = build_prompt(&cwd);
                                let _ = channel.write_all_stdout(prompt.as_bytes()).await;
                                continue;
                            }

                            let byte = match byte {
                                CTRL_P => {
                                    if let Some(entry) = history.previous() {
                                        let _ = terminal.set_buffer(entry);
                                        redraw_line(&mut channel, &terminal).await;
                                    }
                                    continue;
                                }
                                CTRL_N => {
                                    if let Some(entry) = history.next() {
                                        let _ = terminal.set_buffer(entry);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal).await;
                                    continue;
                                }
                                CTRL_W => {
                                    let buffer_copy = AllocString::from(terminal.buffer_str().unwrap_or(""));
                                    let trimmed = buffer_copy.trim_end();
                                    if let Some(last_space) = trimmed.rfind(' ') {
                                        let _ = terminal.set_buffer(&buffer_copy[..last_space + 1]);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal).await;
                                    continue;
                                }
                                CTRL_U => {
                                    terminal.clear_buffer();
                                    redraw_line(&mut channel, &terminal).await;
                                    continue;
                                }
                                other => other,
                            };

                            let key = match terminal.process_byte(byte) {
                                Some(key) => key,
                                None => continue,
                            };

                            match terminal.handle_key(key) {
                                TerminalEvent::CommandReady => {
                                    let _ = channel.write_all_stdout(b"\r\n").await;
                                    if let Ok(cmd) = terminal.take_command() {
                                        let cmd_str = cmd.as_str().trim();
                                        if !cmd_str.is_empty() {
                                            let _ = history.add(cmd_str);
                                        }
                                        let (output, should_exit) = dispatch(cmd_str, &mut cwd);
                                        if !output.is_empty() {
                                            let _ = channel.write_all_stdout(output.as_bytes()).await;
                                        }
                                        if should_exit {
                                            break;
                                        }
                                    }
                                    history.reset_position();
                                    let prompt = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(prompt.as_bytes()).await;
                                }
                                TerminalEvent::EmptyCommand => {
                                    let _ = channel.write_all_stdout(b"\r\n").await;
                                    let prompt = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(prompt.as_bytes()).await;
                                }
                                TerminalEvent::BufferChanged | TerminalEvent::CursorMoved => {
                                    redraw_line(&mut channel, &terminal).await;
                                }
                                TerminalEvent::Interrupt => {
                                    terminal.clear_buffer();
                                    let _ = channel.write_all_stdout(b"^C\r\n").await;
                                    history.reset_position();
                                    let prompt = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(prompt.as_bytes()).await;
                                }
                                TerminalEvent::EndOfFile => break,
                                TerminalEvent::HistoryPrevious => {
                                    if let Some(entry) = history.previous() {
                                        let _ = terminal.set_buffer(entry);
                                        redraw_line(&mut channel, &terminal).await;
                                    }
                                }
                                TerminalEvent::HistoryNext => {
                                    if let Some(entry) = history.next() {
                                        let _ = terminal.set_buffer(entry);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal).await;
                                }
                                _ => {}
                            }
                        }

                        save_history(&history);
                        let _ = channel.exit(0).await;
                    }
                    _ => {
                        let _ = channel
                            .write_all_stderr(b"Only shell mode is supported.\n")
                            .await;
                        let _ = channel.exit(1).await;
                    }
                }
            }
            Err(_) => info!("SSH handshake failed"),
        }

        info!("SSH client disconnected");
    }
}

pub fn spawn(spawner: &Spawner, stack: Stack<'static>) {
    spawner.spawn(task(stack).unwrap());
}
