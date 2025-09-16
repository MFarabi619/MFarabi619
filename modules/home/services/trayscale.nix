{
  lib,
  pkgs,
  ...
}:
{
  services.trayscale = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    hideWindow = true;
  };
}
