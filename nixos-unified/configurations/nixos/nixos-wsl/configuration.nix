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

  system.stateVersion = "24.11";
  networking.hostName = "nixos-wsl";
  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
    # hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
