{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.languages.rust.embassy;
in
{
  options.languages.rust.embassy = {
    enable = lib.mkEnableOption "Embassy (Rust embedded async) development tooling";
  };

  config = lib.mkIf cfg.enable {
    packages =
      (with pkgs; [
        espup
        rustup
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
