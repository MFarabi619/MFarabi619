//! SSH transport and terminal handling for Microvisor.
//!
//! SSH implementation based on [ZSSH](https://github.com/TomCrypto/zssh)
//! by Thomas Bénéteau (MIT license).
//!
//! Terminal handling from [nostd-interactive-terminal](https://github.com/Hahihula/nostd-interactive-terminal)
//! by Petr Gadorek (MIT/Apache-2.0 license).

mod channel;
mod codec;
mod error;
pub mod history;
pub mod parser;
pub mod terminal;
mod transport;
mod types;
mod wire;
pub mod writer;

pub use channel::{Channel, Pipe};
pub use error::{Error, ProtocolError};
pub use transport::Transport;
pub use types::{AuthMethod, Behavior, PublicKey, Request, SecretKey, TransportError};
pub use wire::DisconnectReason;

fn unwrap_unreachable<T>(value: Option<T>) -> T {
    value.unwrap_or_else(|| unreachable!())
}
