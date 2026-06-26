{
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.11";
  networking.hostName = "nixos-vm";
  nixpkgs.config.allowUnfree = true;

  services = {
    qemuGuest.enable = true;
    spice-webdavd.enable = true;
    spice-vdagentd.enable = true;
  };
}
