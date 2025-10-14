{
  lib,
  pkgs,
  ...
}:
{
  services.trayscale = lib.mkIf pkgs.stdenv.isLinux {
    enable = false;
    hideWindow = true;
  };
}
