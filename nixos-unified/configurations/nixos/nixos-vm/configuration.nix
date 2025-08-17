{ config, pkgs, ... }:

{
  system.stateVersion = "25.05";

  imports = [
    ./hardware-configuration.nix
    ../../../modules/nixos/common/networking.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  networking = {
    hostName = "nixos-vm";
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        59010
        59011
        8080
      ];
      allowedUDPPorts = [
        59010
        59011
      ];
    };
  };

  users.users.mfarabi = {
    isNormalUser = true;
    description = "Mumtahin Farabi";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

}
