{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.awww = lib.mkIf pkgs.stdenv.isLinux {
    enable = config.wayland.windowManager.hyprland.enable;
    # extraArgs = [
    #   "--no-cache"
    #   "--layer"
    #   "bottom"
    # ];
  };
}
