{
  lib,
  pkgs,
  config,
  ...
}:
{
  home = {
    shell = {
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableShellIntegration = true;
    };

    shellAliases = {
      cat = "bat";
      man = "batman";
      lg = "lazygit";
      lj = "lazyjournal";
      mkdir = "mkdir -p";
      # mic = "tv microvisor";
      # grep = "batgrep";
      # TODO: add batpipe
    }
    // lib.optionalAttrs (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) {
      # zig = "~/.zvm/bin/zig";
      # stmcli = "/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI";
    };

    sessionVariables =
      lib.mkIf
        (pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64 && config.wayland.windowManager.hyprland.enable)
        {
          XDG_BACKEND = "wayland";
          NIXOS_OZONE_WL = "1";
          MOZ_ENABLE_WAYLAND = "1";
          XDG_RUNTIME_DIR = "/run/user/$(id -u)";
        };

    sessionPath =
      lib.optionals pkgs.stdenv.isLinux [
        # "/home/mfarabi/.zvm/bin"
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "/usr/local/bin"
        "/etc/profiles/per-user/$USER/bin"
        "/nix/var/nix/profiles/system/sw/bin"
      ];
  };
}
