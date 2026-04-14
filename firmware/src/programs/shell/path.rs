use alloc::string::String as AllocString;

use crate::services::{identity, system_files};

pub fn home_dir() -> AllocString {
    identity::home_dir()
}

pub fn ensure_filesystem_hierarchy() {
    system_files::initialize_layout();
}

pub fn display_cwd(cwd: &str) -> AllocString {
    let home = home_dir();
    if cwd == home {
        AllocString::from("~")
    } else if cwd.starts_with(home.as_str()) {
        let mut display_path = AllocString::from("~");
        display_path.push_str(&cwd[home.len()..]);
        display_path
    } else {
        AllocString::from(cwd)
    }
}

pub fn apply_cd(cwd: &mut AllocString, arg: &str) {
    let arg = arg.trim();
    if arg == "~" || arg.is_empty() {
        *cwd = identity::home_dir();
        return;
    }
    if let Some(rest) = arg.strip_prefix("~/") {
        *cwd = identity::home_dir();
        if !rest.is_empty() {
            for part in rest.split('/') {
                match part {
                    "" | "." => {}
                    ".." => {
                        if let Some(position) = cwd.rfind('/') {
                            if position == 0 {
                                cwd.truncate(1);
                            } else {
                                cwd.truncate(position);
                            }
                        }
                    }
                    name => {
                        if cwd != "/" {
                            cwd.push('/');
                        }
                        cwd.push_str(name);
                    }
                }
            }
        }
        return;
    }

    if arg == "/" {
        cwd.clear();
        cwd.push('/');
        return;
    }

    if arg.starts_with('/') {
        cwd.clear();
        cwd.push('/');
    }

    for part in arg.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if let Some(position) = cwd.rfind('/') {
                    if position == 0 {
                        cwd.truncate(1);
                    } else {
                        cwd.truncate(position);
                    }
                }
            }
            name => {
                if cwd != "/" {
                    cwd.push('/');
                }
                cwd.push_str(name);
            }
        }
    }
}

pub fn resolve_path(cwd: &str, name: &str) -> AllocString {
    if name.starts_with('/') {
        AllocString::from(name)
    } else {
        let mut path = AllocString::from(cwd);
        if !path.ends_with('/') {
            path.push('/');
        }
        path.push_str(name);
        path
    }
}
