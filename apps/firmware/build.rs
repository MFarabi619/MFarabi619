fn main() {
    if let Ok(dotconfig) = std::env::var("DOTCONFIG") {
        if std::path::Path::new(&dotconfig).exists() {
            let flags = zephyr_build::extract_kconfig_bool_options(&dotconfig)
                .expect("failed to extract Kconfig flags");
            for flag in &flags {
                println!("cargo:rustc-cfg={flag}");
            }
            if flags.iter().any(|f| f == "CONFIG_SQLITE") {
                generate_sqlite_bindings();
            }
            println!("cargo:rerun-if-env-changed=DOTCONFIG");
            println!("cargo:rerun-if-changed={dotconfig}");
        }
    }
    if let Ok(dts) = std::env::var("ZEPHYR_DTS") {
        if std::path::Path::new(&dts).exists() {
            zephyr_build::dt_cfgs();
        }
    }
}

fn generate_sqlite_bindings() {
    let header = "../../libs/zephyr-lib-sqlite/sqlite3ext.h";
    println!("cargo:rerun-if-changed={header}");
    let bindings = bindgen::Builder::default()
        .header(header)
        .clang_arg("-fvisibility=default")
        .use_core()
        .generate()
        .expect("bindgen failed on sqlite3ext.h");
    let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_dir.join("sqlite_bindings.rs"))
        .expect("failed writing sqlite_bindings.rs");
}
