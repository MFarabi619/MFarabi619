use std::{env, fs::File, io::Write, path::PathBuf};

fn main() {
    let target = std::env::var("TARGET").expect("TARGET not set");

    if target == "thumbv7em-none-eabihf" {
        stm32();
    } else if target.starts_with("xtensa-esp32") && target.ends_with("-none-elf") {
        esp32();
    }
}

fn stm32() {
    //! This build script copies the `memory.stm32.x` file from the crate root into
    //! a directory where the linker can always find it at build time.
    //! For many projects this is optional, as the linker always searches the
    //! project root directory -- wherever `Cargo.toml` is. However, if you
    //! are using a workspace or have a more complicated build setup, this
    //! build script becomes required. Additionally, by requesting that
    //! Cargo re-run the build script whenever `memory.stm32.x` is changed,
    //! updating `memory.stm32.x` ensures a rebuild of the application with the
    //! new memory settings.

    // Put `memory.x` in our output directory and ensure it's
    // on the linker search path.
    let out = &PathBuf::from(env::var_os("OUT_DIR").unwrap());
    File::create(out.join("memory.x"))
        .unwrap()
        .write_all(include_bytes!("memory.stm32.x"))
        .unwrap();
    println!("cargo:rustc-link-search={}", out.display());

    // By default, Cargo will re-run a build script whenever
    // any file in the project changes. By specifying `memory.stm32.x`
    // here, we ensure the build script is only re-run when
    // `memory.stm32.x` is changed.
    println!("cargo:rerun-if-changed=memory.stm32.x");

    println!("cargo:rustc-link-arg-bins=--nmagic");
    println!("cargo:rustc-link-arg-bins=-Tlink.x");
    println!("cargo:rustc-link-arg-bins=-Tdefmt.x");
}

fn esp32() {
    // Compile-time device configuration. These are read by
    // firmware/src/config.rs via env!() / option_env!().
    // Override any of these by setting the env var before cargo:
    //   NETWORK_WIFI_SSID=mynet cargo b
    set_env_default("NETWORK_WIFI_SSID", "");
    set_env_default("NETWORK_WIFI_PSK", "");
    set_env_default("SHELL_USER", "");
    set_env_default("HOSTNAME", "");

    linker_be_nice();
    println!("cargo:rustc-link-arg=-nostartfiles");
    println!("cargo:rustc-link-arg-tests=-Tembedded-test.x");
    println!("cargo:rustc-link-arg=-Tdefmt.x");
    println!("cargo:rustc-link-arg=-Tlinkall.x");
}

fn set_env_default(key: &str, default_value: &str) {
    let value = env::var(key).unwrap_or_else(|_| default_value.to_string());
    println!("cargo:rustc-env={key}={value}");
    println!("cargo:rerun-if-env-changed={key}");
}

fn linker_be_nice() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 {
        let kind = &args[1];
        let what = &args[2];

        match kind.as_str() {
            "undefined-symbol" => match what.as_str() {
                what if what.starts_with("_defmt_") => {
                    eprintln!();
                    eprintln!(
                        "💡 `defmt` not found - make sure `defmt.x` is added as a linker script and you have included `use defmt_rtt as _;`"
                    );
                    eprintln!();
                }
                "_stack_start" => {
                    eprintln!();
                    eprintln!("💡 Is the linker script `linkall.x` missing?");
                    eprintln!();
                }
                what if what.starts_with("esp_rtos_") => {
                    eprintln!();
                    eprintln!(
                        "💡 `esp-radio` has no scheduler enabled. Make sure you have initialized `esp-rtos` or provided an external scheduler."
                    );
                    eprintln!();
                }
                "embedded_test_linker_file_not_added_to_rustflags" => {
                    eprintln!();
                    eprintln!(
                        "💡 `embedded-test` not found - make sure `embedded-test.x` is added as a linker script for tests"
                    );
                    eprintln!();
                }
                "free"
                | "malloc"
                | "calloc"
                | "get_free_internal_heap_size"
                | "malloc_internal"
                | "realloc_internal"
                | "calloc_internal"
                | "free_internal" => {
                    eprintln!();
                    eprintln!(
                        "💡 Did you forget the `esp-alloc` dependency or didn't enable the `compat` feature on it?"
                    );
                    eprintln!();
                }
                _ => (),
            },
            // we don't have anything helpful for "missing-lib" yet
            _ => {
                std::process::exit(1);
            }
        }

        std::process::exit(0);
    }

    println!(
        "cargo:rustc-link-arg=-Wl,--error-handling-script={}",
        std::env::current_exe().unwrap().display()
    );
}
