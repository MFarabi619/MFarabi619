# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    flake.inputs.stylix.nixosModules.stylix
    flake.inputs.nix-dokploy.nixosModules.default
    ./configuration.nix
  ];

  nixos-unified.sshTarget = "nixos-utm";

  virtualisation.docker.daemon.settings.live-restore = false;

  services = {
    dokploy = {
      enable = false;
      port = "127.0.0.1:8000:3000";

      swarm = {
        autoRecreate = true;
        # advertiseAddress = "private";
        # advertiseAddress = {
        #  command = "echo 192.168.1.100";
        #   command = "tailscale ip -4 | head -n1";
        #   # extraPackages = [ pkgs.tailscale ];
        # };
      };
    };
  };
}
