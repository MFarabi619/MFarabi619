{
  pkgs,
  lib,
  ...
}:
{
  services = lib.mkIf pkgs.stdenv.isLinux {
    swww = {
      enable = true;
      # extraArgs = [
      #   "--no-cache"
      #   "--layer"
      #   "bottom"
      # ];
    };
  };
}
