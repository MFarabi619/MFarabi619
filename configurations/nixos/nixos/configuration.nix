{
  lib,
  pkgs,
  config,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos";
  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;
  nixos-unified.sshTarget = config.networking.hostName;
}
