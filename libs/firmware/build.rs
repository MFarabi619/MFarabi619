fn main() {
    let dotconfig = std::env::var("DOTCONFIG").expect("DOTCONFIG must be set by Zephyr CMake");
    let flags = zephyr_build::extract_kconfig_bool_options(&dotconfig)
        .expect("failed to extract Kconfig flags");
    for flag in &flags {
        println!("cargo:rustc-cfg={flag}");
        println!("cargo:rustc-check-cfg=cfg({flag})");
    }
    for cfg in [
        "CONFIG_MODEM_CELLULAR",
        "CONFIG_WIREGUARD",
        "CONFIG_SNTP",
        "CONFIG_MCUMGR_TRANSPORT_UDP",
    ] {
        println!("cargo:rustc-check-cfg=cfg({cfg})");
    }
    println!("cargo:rerun-if-env-changed=DOTCONFIG");
    println!("cargo:rerun-if-changed={dotconfig}");
}
