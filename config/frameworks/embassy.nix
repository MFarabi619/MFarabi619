{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.languages.rust.embassy;
  default_firmware_dir =
    if config ? git && config.git ? root then "${config.git.root}/firmware" else "./firmware";
  final_firmware_dir = lib.defaultTo default_firmware_dir cfg.firmwareDir;
  default_runner = "espflash flash --chip ${cfg.chip} --monitor --monitor-baud ${toString cfg.monitor_baud} --log-format defmt";

  typed_rust_toolchain = {
    toolchain.channel = cfg.toolchain;
  };

  typed_cargo_config = {
    env = lib.optionalAttrs (cfg.cargo.env.DEFMT_LOG != null) {
      DEFMT_LOG = cfg.cargo.env.DEFMT_LOG;
    };

    build = {
      target = cfg.cargo.build.target;
      rustflags = cfg.cargo.build.rustflags;
    };

    unstable = {
      "build-std" = cfg.cargo.unstable."build-std";
    };

    target = {
      "${cfg.cargo.build.target}" = {
        runner = lib.defaultTo default_runner cfg.cargo.runner;
      };
    };
  };

  final_rust_toolchain = lib.recursiveUpdate typed_rust_toolchain cfg.extraRustToolchain;
  final_cargo_config = lib.recursiveUpdate typed_cargo_config cfg.extraCargoConfig;
in
{
  options.languages.rust.embassy = {
    enable = lib.mkEnableOption "Embassy (Rust embedded async) development tooling";

    writeConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to generate firmware/rust-toolchain.toml and firmware/.cargo/config.toml.";
    };

    firmwareDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the firmware directory. Defaults to `${default_firmware_dir}`.";
    };

    chip = lib.mkOption {
      type = lib.types.str;
      default = "esp32s3";
      description = "Espressif chip for flashing/monitoring workflows.";
    };

    baud = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1500000;
      description = "Baud rate for esptool flashing tasks.";
    };

    monitor_baud = lib.mkOption {
      type = lib.types.ints.positive;
      default = 115200;
      description = "Monitor baud rate for espflash runner generation.";
    };

    after = lib.mkOption {
      type = lib.types.str;
      default = "hard-reset";
      description = "esptool --after value.";
    };

    before = lib.mkOption {
      type = lib.types.str;
      default = "default-reset";
      description = "esptool --before value.";
    };

    port = lib.mkOption {
      type = lib.types.str;
      default = "rfc2217://rpi5-16:2217?ign_set_control";
      description = "Serial port URI used by flashing tasks.";
    };

    toolchain = lib.mkOption {
      type = lib.types.str;
      default = "esp";
      description = "Rust toolchain channel written to rust-toolchain.toml.";
    };

    cargo = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = {
          env = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                DEFMT_LOG = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = "info";
                };
              };
            };
          };

          build = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                target = lib.mkOption {
                  type = lib.types.str;
                  default = "xtensa-esp32s3-none-elf";
                };

                rustflags = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "-C"
                    "link-arg=-nostartfiles"
                  ];
                };
              };
            };
          };

          unstable = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                "build-std" = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "alloc"
                    "core"
                  ];
                };
              };
            };
          };

          runner = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Runner command for [target.<triple>].runner; null derives from chip and monitor_baud.";
          };
        };
      };
    };

    extraRustToolchain = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Deep-merged into rust-toolchain.toml after typed config.";
    };

    extraCargoConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Deep-merged into .cargo/config.toml after typed config.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (!cfg.writeConfig) || final_firmware_dir != null;
        message = "languages.rust.embassy.writeConfig is true, but firmwareDir resolved to null.";
      }
    ];

    packages =
      (with pkgs; [
        espup
        rustup
        openocd
        esptool
        ldproxy
        espflash
        esp-generate
        probe-rs-tools
        cargo-espmonitor
      ])
      ++ lib.optionals pkgs.stdenv.isDarwin (
        with pkgs;
        [
          binsider
        ]
      );

    files = lib.mkIf cfg.writeConfig {
      "${final_firmware_dir}/rust-toolchain.toml".toml = final_rust_toolchain;
      "${final_firmware_dir}/.cargo/config.toml".toml = final_cargo_config;
    };

    enterShell = lib.mkAfter ''
      if [ -f "\$\{ESPUP_EXPORT_FILE:-}" ]; then
        . "$ESPUP_EXPORT_FILE"
      elif [ -f "$HOME/export-esp.sh" ]; then
        . "$HOME/export-esp.sh"
      fi

      if command -v xtensa-esp-elf-gcc >/dev/null 2>&1; then
        echo -e "\033[36m[devenv:embassy]:\033[0m\033[32m Espressif Rust toolchain ready 🦀\033[0m"
      else
        echo -e "\033[36m[devenv:embassy]:\033[0m\033[34m xtensa-esp-elf-gcc \033[0m\033[31mtoolchain not found ⚠️\033[0m"
        echo -e "\033[36m[devenv:embassy]:\033[0m\033[33m install with \033[0m\033[35mespup install && direnv allow\033[0m\n"
      fi
    '';
  };
}
