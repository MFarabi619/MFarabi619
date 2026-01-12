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

    dokploy = {
      enable = true;
      port = "127.0.0.1:80:3000";

      swarm = {
        autoRecreate = true;
        advertiseAddress = "private";
        # advertiseAddress = {
        #  command = "echo 192.168.1.100";
        #   command = "tailscale ip -4 | head -n1";
        #   # extraPackages = [ pkgs.tailscale ];
        # };
      };
    };
  };
}
