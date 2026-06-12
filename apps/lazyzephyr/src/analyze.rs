use std::{fs, path::PathBuf};

use elf::{ElfBytes, endian::AnyEndian};
use lazyzephyr_core::commands::elf::ElfInfo;

use crate::elf_inspect::{Property, header::FileHeaders};

pub fn load() -> ElfInfo {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = PathBuf::from(home).join("MFarabi619/build/MFarabi619/zephyr/zephyr.elf");
    let path_s = path.to_string_lossy().into_owned();

    let bytes = match fs::read(&path) {
        Ok(b) => b,
        Err(error) => {
            return ElfInfo {
                path: path_s,
                error: Some(format!("{error}")),
                ..ElfInfo::default()
            };
        }
    };

    let parsed = match ElfBytes::<AnyEndian>::minimal_parse(&bytes) {
        Ok(p) => p,
        Err(error) => {
            return ElfInfo {
                path: path_s,
                error: Some(format!("{error}")),
                ..ElfInfo::default()
            };
        }
    };

    let headers = FileHeaders::from(parsed.ehdr);
    let pairs: Vec<(String, String)> = headers
        .items()
        .into_iter()
        .filter_map(|row| {
            let mut iter = row.into_iter();
            let key = iter.next()?;
            let value = iter.next().unwrap_or_default();
            Some((key, value))
        })
        .collect();

    ElfInfo {
        path: path_s,
        headers: pairs,
        error: None,
    }
}
