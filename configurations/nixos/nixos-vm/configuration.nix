{
  lib,
  pkgs,
  config,
  ...
}:

{

  imports = [
    ./hardware-configuration.nix
    ../../../modules/nixos/networking
  ];

  system.stateVersion = "25.11";
  networking.hostName = "nixos-vm";
  nixpkgs.config.allowUnfree = true;

  services = {
    qemuGuest.enable = true;
    spice-webdavd.enable = true;
    spice-vdagentd.enable = true;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

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
}
