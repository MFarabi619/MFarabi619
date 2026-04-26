use alloc::string::String as AllocString;
use ed25519_dalek::SigningKey;
use esp_hal::rng::Rng;

use crate::{config::app, filesystems::sd};

pub fn ssh_user() -> &'static str {
    app::SSH_USER
}

pub fn hostname() -> &'static str {
    app::HOSTNAME
}

pub fn home_dir() -> AllocString {
    let mut home = AllocString::from("/home/");
    home.push_str(ssh_user());
    home
}

fn join_path(base_path: &str, path_segment: &str) -> AllocString {
    if path_segment.starts_with('/') {
        AllocString::from(path_segment)
    } else {
        let mut path = AllocString::from(base_path);
        if !path.ends_with('/') {
            path.push('/');
        }
        path.push_str(path_segment);
        path
    }
}

fn home_dir_name_upper() -> AllocString {
    let mut upper = AllocString::new();
    for character in ssh_user().chars() {
        upper.push(character.to_ascii_uppercase());
    }
    upper
}

pub fn ensure_home_hierarchy() {
    let _ = sd::create_directory("HOME");
    let home = home_dir();
    let _ = sd::mkdir_at("/home", &home_dir_name_upper());
    let _ = sd::mkdir_at(home.as_str(), ".SSH");
    let _ = sd::mkdir_at(home.as_str(), ".CACHE");
    let _ = sd::mkdir_at(home.as_str(), ".LOCAL");

    let ssh_dir = join_path(home.as_str(), ".ssh");
    if sd::read_file_at::<64>(ssh_dir.as_str(), "AUTH_KEY").is_err() {
        let _ = sd::touch_at(ssh_dir.as_str(), "AUTH_KEY");
    }

    if sd::read_file_at::<64>(home.as_str(), ".MSHRC").is_err() {
        let _ = sd::write_file_at(home.as_str(), ".MSHRC", b"microfetch\n");
    }
}

pub fn load_or_generate_host_key() -> [u8; 32] {
    let home = home_dir();
    let ssh_dir = join_path(home.as_str(), ".ssh");

    if let Ok(contents) = sd::read_file_at::<32>(ssh_dir.as_str(), app::SSH_HOST_KEY_FILE) {
        if contents.len() == 32 {
            let mut key = [0u8; 32];
            key.copy_from_slice(contents.as_slice());
            return key;
        }
    }

    let rng = Rng::new();
    let mut key = [0u8; 32];
    for chunk in key.chunks_mut(4) {
        let random = rng.random();
        let bytes = random.to_le_bytes();
        chunk.copy_from_slice(&bytes[..chunk.len()]);
    }

    let _ = sd::write_file_at(ssh_dir.as_str(), app::SSH_HOST_KEY_FILE, &key);
    defmt::info!("generated new SSH host key");
    key
}

pub fn signing_key() -> SigningKey {
    SigningKey::from_bytes(&load_or_generate_host_key())
}
