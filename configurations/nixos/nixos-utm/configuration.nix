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
  networking.hostName = "nixos-utm";
  nixpkgs.config.allowUnfree = true;
  nixos-unified.sshTarget = config.networking.hostName;
  virtualisation.docker.daemon.settings.live-restore = false;

  services = {
    qemuGuest.enable = true;
    spice-webdavd.enable = true;
    spice-vdagentd.enable = true;
  };
}
