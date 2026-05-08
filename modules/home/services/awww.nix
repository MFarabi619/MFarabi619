{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.awww = lib.mkIf pkgs.stdenv.isLinux {
    enable = config.wayland.enable;
    # extraArgs = [
    #   "--no-cache"
    #   "--layer"
    #   "bottom"
    # ];
  };
}
