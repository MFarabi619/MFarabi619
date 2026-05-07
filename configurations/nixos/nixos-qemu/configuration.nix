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

  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;
  networking.hostName = "nixos-utm";
  nixos-unified.sshTarget = config.networking.hostName;
}
