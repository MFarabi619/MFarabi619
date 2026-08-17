{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.awww = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = config.wayland.windowManager.hyprland.enable;
    # extraArgs = [
    #   "--no-cache"
    #   "--layer"
    #   "bottom"
    # ];
  };
}
