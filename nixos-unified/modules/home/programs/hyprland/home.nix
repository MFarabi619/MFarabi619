{lib, pkgs, ...}:
{
  home = lib.mkIf pkgs.stdenv.isLinux {
    packages = with pkgs; [
      wl-clipboard
    ];

    sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
    };
  };
}
