fn main() {
    let Ok(dotconfig) = std::env::var("DOTCONFIG") else {
        return;
    };
    if !std::path::Path::new(&dotconfig).exists() {
        return;
    }

    let flags = zephyr_build::extract_kconfig_bool_options(&dotconfig)
        .expect("failed to extract Kconfig flags");
    for flag in &flags {
        println!("cargo:rustc-cfg={flag}");
    }

    if flags.iter().any(|flag| flag == "CONFIG_SQLITE") {
        generate_sqlite_bindings();
    }

    println!("cargo:rerun-if-changed={dotconfig}");
    println!("cargo:rerun-if-env-changed=DOTCONFIG");
    println!("cargo:rerun-if-env-changed=INCLUDE_DIRS");
}

fn generate_sqlite_bindings() {
    let include_dirs = std::env::var("INCLUDE_DIRS").unwrap_or_default();
    let mut builder = bindgen::Builder::default()
        .header_contents("sqlite_wrapper.h", "#include <sqlite3ext.h>\n")
        .clang_arg("-fvisibility=default")
        .use_core();
    for dir in include_dirs.split([';', ' ']).filter(|dir| !dir.is_empty()) {
        builder = builder.clang_arg(format!("-I{dir}"));
    }
    let bindings = builder
        .generate()
        .expect("bindgen failed on sqlite3ext.h");
    let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_dir.join("sqlite_bindings.rs"))
        .expect("failed writing sqlite_bindings.rs");
}
