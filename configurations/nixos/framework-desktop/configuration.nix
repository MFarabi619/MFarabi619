# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

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

  system.stateVersion = "25.05";
  networking.hostName = "framework-desktop";
  nixpkgs.config.allowUnfree = true;

  users.users.mfarabi = {
    isNormalUser = true;
    description = "Mumtahin Farabi";

    extraGroups = [
      "wheel"
      "video"
    ]
    ++ lib.optionals config.virtualisation.docker.enable [
      "docker"
    ]
    ++ lib.optionals config.networking.networkmanager.enable [
      "networkmanager"
    ];
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
}
