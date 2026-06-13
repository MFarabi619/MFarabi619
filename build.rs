fn main() {
    // Under west/Zephyr CMake, DOTCONFIG points at the merged .config so we can
    // emit a cfg per enabled CONFIG_X. When the env is absent (rust-analyzer or
    // bare cargo check), skip extraction — emit only check-cfgs so cross-board
    // `#[cfg(CONFIG_X)]` references don't trigger unexpected_cfg warnings.
    if let Ok(dotconfig) = std::env::var("DOTCONFIG") {
        let flags = zephyr_build::extract_kconfig_bool_options(&dotconfig)
            .expect("failed to extract Kconfig flags");
        for flag in &flags {
            println!("cargo:rustc-cfg={flag}");
            println!("cargo:rustc-check-cfg=cfg({flag})");
        }
        println!("cargo:rerun-if-env-changed=DOTCONFIG");
        println!("cargo:rerun-if-changed={dotconfig}");
    }
    // DT-based cfgs enable #[cfg(dt = "labels::<name>")]. Requires Zephyr's CMake
    // env (ZEPHYR_DTS + BINARY_DIR_INCLUDE_GENERATED); skip otherwise.
    if std::env::var("ZEPHYR_DTS").is_ok() {
        zephyr_build::dt_cfgs();
    }
    println!("cargo:rustc-check-cfg=cfg(dt, values(any()))");
    for cfg in [
        "CONFIG_WIREGUARD",
        "CONFIG_MCUMGR_TRANSPORT_UDP",
        "CONFIG_NET_DHCPV4_SERVER",
        "CONFIG_NET_PKT_FILTER_IPV4_HOOK",
    ] {
        println!("cargo:rustc-check-cfg=cfg({cfg})");
    }
}
