# docker service update --env-add TZ=America/Toronto dokploy_dokploy
{
  pkgs,
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
    port = "1212:3000";
    image = "dokploy/dokploy:v0.27.1";
    enable = config.networking.hostName == "framework-desktop";

    environment = {
      TZ = config.time.timeZone;
    };

    swarm = {
      autoRecreate = true;
      advertiseAddress =
        if config.services.tailscale.enable then
          {
            command = "tailscale ip -4 | head -n1";
            extraPackages = [ pkgs.tailscale ];
          }
        else
          "private";
    };
  };
}
