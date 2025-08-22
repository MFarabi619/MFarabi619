{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./wsl.nix
  ];

  system.stateVersion = "25.05";
  networking.hostName = "nixos-wsl";
  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
    # hostPlatform = lib.mkDefault "x86_64-linux";
  };
  services.seatd = {
    enable = true;
    user = "root"; # default
    group = "seat"; # default
  };
}
