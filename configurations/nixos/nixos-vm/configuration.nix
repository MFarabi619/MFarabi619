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

  nixpkgs = {
    config.allowUnfree = true;
    # hostPlatform = "x86_64-linux";
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
