{
  pkgs,
  ...
}:

{

  imports = [
    ./hardware-configuration.nix
    ../../../modules/nixos/networking
  ];

  system.stateVersion = "25.05";
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
      "networkmanager"
    ];
  };
}
