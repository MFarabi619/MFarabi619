fn main() {
    if let Ok(dotconfig) = std::env::var("DOTCONFIG") {
        if std::path::Path::new(&dotconfig).exists() {
            let flags = zephyr_build::extract_kconfig_bool_options(&dotconfig)
                .expect("failed to extract Kconfig flags");
            for flag in &flags {
                println!("cargo:rustc-cfg={flag}");
            }
            println!("cargo:rerun-if-changed={dotconfig}");
        }
    }
}
