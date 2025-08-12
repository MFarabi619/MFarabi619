{ pkgs, lib, ... }:
{
  services.home-manager = {
    autoExpire = {
      enable = true;
      frequency = "daily";
    };
    autoUpgrade = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      frequency = "daily";
    };
  };
}
