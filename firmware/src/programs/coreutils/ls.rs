use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::console::icons;
use crate::filesystems::sd::list_directory_at;
use crate::programs::shell;

/// (extension, glyph, ANSI color)
const FILE_TYPES: &[(&str, &str, &str)] = &[
    ("rs",   icons::NF_DEV_RUST,       "\x1b[33m"),
    ("toml", icons::NF_SETI_TOML,      "\x1b[32m"),
    ("json", icons::NF_SETI_JSON,      "\x1b[32m"),
    ("csv",  icons::NF_FA_DATABASE,    "\x1b[36m"),
    ("db",   icons::NF_FA_DATABASE,    "\x1b[36m"),
    ("txt",  icons::NF_FA_FILE_TEXT,   "\x1b[0m"),
    ("log",  icons::NF_FA_FILE_TEXT,   "\x1b[0m"),
    ("md",   icons::NF_SETI_MARKDOWN,  "\x1b[1;33m"),
    ("org",  icons::NF_SETI_ORG,       "\x1b[1;33m"),
    ("html", icons::NF_DEV_HTML5,      "\x1b[35m"),
    ("htm",  icons::NF_DEV_HTML5,      "\x1b[35m"),
    ("js",   icons::NF_DEV_JAVASCRIPT, "\x1b[33m"),
    ("css",  icons::NF_DEV_CSS3,       "\x1b[35m"),
    ("wasm", icons::NF_SETI_WASM,      "\x1b[35m"),
    ("was",  icons::NF_SETI_WASM,      "\x1b[35m"),
    ("svg",  icons::NF_FA_FILE_IMAGE,  "\x1b[35m"),
    ("png",  icons::NF_FA_FILE_IMAGE,  "\x1b[35m"),
    ("jpg",  icons::NF_FA_FILE_IMAGE,  "\x1b[35m"),
    ("bin",  icons::NF_MD_BINARY,      "\x1b[2m"),
    ("dat",  icons::NF_MD_BINARY,      "\x1b[2m"),
    ("lock", icons::NF_FA_LOCK,        "\x1b[2m"),
    ("nix",  icons::NF_LINUX_NIX,      "\x1b[34m"),
];

/// (directory name, glyph) — matched case-insensitively
const DIR_TYPES: &[(&str, &str)] = &[
    ("desktop",   icons::NF_FA_DESKTOP),
    ("pictures",  icons::NF_MD_PICTURE),
    ("downloads", icons::NF_FA_DOWNLOAD),
    ("documents", icons::NF_MD_DOCUMENT),
    ("home",      icons::NF_FA_HOME),
    (".config",   icons::NF_SETI_CONFIG),
    ("public",    icons::NF_MD_PUBLIC),
    ("tmp",       icons::NF_MD_TEMP),
    (".ssh",      icons::NF_MD_SSH),
];

const DIR_COLOR: &str = "\x1b[1;34m";

fn file_ext(name: &str) -> Option<&str> {
    name.rsplit('.').next()
}

fn lookup_file(name: &str) -> (&'static str, &'static str) {
    if let Some(ext) = file_ext(name) {
        for &(e, glyph, color) in FILE_TYPES {
            if ext.eq_ignore_ascii_case(e) {
                return (glyph, color);
            }
        }
    }
    (icons::NF_FA_FILE, "\x1b[0m")
}

fn lookup_dir(name: &str) -> &'static str {
    for &(dir_name, glyph) in DIR_TYPES {
        if name.eq_ignore_ascii_case(dir_name) {
            return glyph;
        }
    }
    icons::NF_FA_FOLDER
}

pub fn run(cwd: &str) -> AllocString {
    let mut out = AllocString::new();

    match list_directory_at(cwd) {
        Ok(entries) => {
            if entries.is_empty() {
                let _ = write!(out, "\x1b[2m(empty)\x1b[0m\r\n");
                return out;
            }

            let mut dirs = heapless::Vec::<usize, 64>::new();
            let mut files = heapless::Vec::<usize, 64>::new();

            for (i, entry) in entries.iter().enumerate() {
                if entry.is_directory {
                    let _ = dirs.push(i);
                } else {
                    let _ = files.push(i);
                }
            }

            let mut display_entries = heapless::Vec::<AllocString, 64>::new();
            let mut max_width: usize = 0;

            for &i in dirs.iter() {
                let entry = &entries[i];
                let name = to_lower(entry.name.as_str());
                let glyph = lookup_dir(&name);
                let mut s = AllocString::new();
                let _ = write!(s, "{}{} {}/\x1b[0m", DIR_COLOR, glyph, name);
                let vis_width = 2 + 1 + name.len() + 1;
                if vis_width > max_width { max_width = vis_width; }
                let _ = display_entries.push(s);
            }

            for &i in files.iter() {
                let entry = &entries[i];
                let name = to_lower(entry.name.as_str());
                let (glyph, color) = lookup_file(&name);
                let mut s = AllocString::new();
                let _ = write!(s, "{}{} {}\x1b[0m", color, glyph, name);
                let vis_width = 2 + 1 + name.len();
                if vis_width > max_width { max_width = vis_width; }
                let _ = display_entries.push(s);
            }

            let term_width = shell::terminal_width() as usize;
            let col_width = max_width + 2;
            let num_cols = if col_width > 0 { (term_width / col_width).max(1) } else { 1 };
            let num_rows = (display_entries.len() + num_cols - 1) / num_cols;

            for row in 0..num_rows {
                for col in 0..num_cols {
                    let idx = col * num_rows + row;
                    if idx < display_entries.len() {
                        let entry_str = &display_entries[idx];
                        let _ = write!(out, "{}", entry_str);

                        let vis_idx = if idx < dirs.len() {
                            let ei = dirs[idx];
                            2 + 1 + entries[ei].name.len() + 1
                        } else {
                            let fi = idx - dirs.len();
                            if fi < files.len() {
                                let ei = files[fi];
                                2 + 1 + entries[ei].name.len()
                            } else {
                                0
                            }
                        };

                        if col < num_cols - 1 {
                            let pad = col_width.saturating_sub(vis_idx);
                            for _ in 0..pad {
                                out.push(' ');
                            }
                        }
                    }
                }
                let _ = write!(out, "\r\n");
            }
        }
        Err(error) => return super::fmt_error(&error),
    }

    let _ = write!(out, "\r\n");
    out
}

fn to_lower(s: &str) -> AllocString {
    let mut lower = AllocString::new();
    for c in s.chars() {
        lower.push(c.to_ascii_lowercase());
    }
    lower
}
