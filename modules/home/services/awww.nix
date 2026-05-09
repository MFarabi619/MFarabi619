{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.awww = lib.mkIf pkgs.stdenv.isLinux {
    # `config.wayland.enable` doesn't exist as an option — was breaking eval.
    # Gate on hyprland (the wayland compositor we actually use); flip to false
    # for hosts without a graphical session.
    # enable = config.wayland.windowManager.hyprland.enable or false;
    enable = config.programs.wayland.enable;
    # extraArgs = [
    #   "--no-cache"
    #   "--layer"
    #   "bottom"
    # ];
  };
}
