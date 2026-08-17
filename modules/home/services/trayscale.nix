{
  lib,
  pkgs,
  ...
}:
{
  services.trayscale = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = false;
    hideWindow = true;
  };
}
