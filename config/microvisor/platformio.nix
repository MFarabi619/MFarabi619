{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.platformio;
in
{
  # platformio.ini is now tangled from CONTRIBUTING.org

  options.platformio = {
    enable = lib.mkEnableOption "PlatformIO Development Tooling for Embedded Systems.";
  };

  config = lib.mkIf cfg.enable {
    packages =
      (with pkgs; [
        ninja
        ccache
        openocd
        esptool
      ])
      ++ lib.optionals pkgs.stdenv.isDarwin (
        with pkgs;
        [
          dfu-util
          kconfig-frontends
          python314Packages.kconfiglib
        ]
      );

    enterShell = lib.mkAfter ''
      echo -e "\033[36m[devenv:platformio]:\033[0m\033[32m Platformio workspace ready 🟧\033[0m"
    '';
  };
}
