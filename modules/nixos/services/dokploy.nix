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
    enable = config.networking.hostName == "framework-desktop";
    port = "1212:3000";

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
