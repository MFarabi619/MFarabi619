{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.microvisor.embassy;
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
  defaultCwd =
    let
      gitRoot = lib.attrByPath [ "git" "root" ] null config;
    in
    if gitRoot == null then "./" else "${gitRoot}";
  finalCwd = lib.defaultTo defaultCwd cfg.cwd;
  wokwi = cfg.wokwi;
  wokwiToml = builtins.removeAttrs wokwi [ "diagram" ];
  wokwiDiagram = lib.attrByPath [ "diagram" ] null wokwi;
in
{
  options.microvisor.embassy = {
    enable = lib.mkEnableOption "Embassy (Rust embedded async) development tooling";

    cwd = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Working directory where firmware config files are generated. Defaults to `${defaultCwd}`.";
    };

    wokwi = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Wokwi config map. Supports TOML keys and an optional diagram key for JSON output.";
    };

    "probe-rs" = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Raw TOML attrset rendered directly to .probe-rs.toml when non-empty.";
    };
  };

  config = lib.mkIf cfg.enable {
    packages =
      (with pkgs-unstable; [
        SDL2 # for embedded TUI simulator
        espup
        rustup
        openocd
        esptool
        ldproxy
        espflash
        esp-generate
        cargo-embassy
        cargo-generate
        (probe-rs-tools.overrideAttrs (old: {
          cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "remote" ];
        }))
      ])
      ++ lib.optionals pkgs.stdenv.isDarwin (
        with pkgs-unstable;
        [
          binsider
        ]
      );

    files =
      lib.optionalAttrs (wokwiToml != { }) {
        "${finalCwd}/wokwi.toml".toml = {
          wokwi = wokwiToml;
        };
      }
      // lib.optionalAttrs (wokwiDiagram != null) {
        "${finalCwd}/diagram.json".json = wokwiDiagram;
      }
      // lib.optionalAttrs (cfg."probe-rs" != { }) {
        "${finalCwd}/.probe-rs.toml".toml = cfg."probe-rs";
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
