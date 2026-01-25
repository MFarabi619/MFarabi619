# docker service update --env-add TZ=America/Toronto dokploy_dokploy
{
  flake,
  config,
  ...
}:
{
  imports = [
    flake.inputs.nix-dokploy.nixosModules.default
  ];

  virtualisation.docker.daemon.settings.live-restore = false;

  services.dokploy = {
    # enable = false;
    enable = config.networking.hostName == "framework-desktop";
    # lxc = false; # default
    port = "1212:3000";
    # dataDir = "/etc/dokploy"; # default
    # traefik = "traefik:v3.6.1"; # default
    image = "dokploy/dokploy:v0.26.5";

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
}
