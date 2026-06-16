fn main() {
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
    if std::env::var("ZEPHYR_DTS").is_ok() {
        zephyr_build::dt_cfgs();
    }
    println!("cargo:rustc-check-cfg=cfg(dt, values(any()))");
    for cfg in [
        "CONFIG_WIREGUARD",
        "CONFIG_NET_DHCPV4_SERVER",
        "CONFIG_NET_PKT_FILTER_IPV4_HOOK",
        "CONFIG_NETWORKING",
    ] {
        println!("cargo:rustc-check-cfg=cfg({cfg})");
    }
}
