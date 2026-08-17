{
  pkgs,
  lib,
  ...
}:
{
  services.home-manager = {
    autoExpire = {
      enable = true;
      frequency = "daily";
    };

    autoUpgrade = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      frequency = "daily";
    };
  };
}
