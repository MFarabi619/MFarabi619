{
  pkgs,
  flake,
  config,
  ...
}:
{
  imports = [
    (import "${flake.inputs.nixpkgs.legacyPackages.x86_64-linux.applyPatches {
      name = "nix-dokploy-caddy-traefik-ports";
      src = flake.inputs.nix-dokploy;
      postPatch = ''
        substituteInPlace nix-dokploy.nix \
          --replace-fail '-p 80:80/tcp' '-p 81:80/tcp' \
          --replace-fail '-p 443:443/tcp' '-p 444:443/tcp' \
          --replace-fail '-p 443:443/udp' '-p 444:443/udp'
      '';
    }}/nix-dokploy.nix")
  ];

  virtualisation.docker.daemon.settings.live-restore = false;

  # docker service update --env-add TZ=America/Toronto dokploy_dokploy
  services.dokploy = {
    port = "1212:3000";
    enable = true;
    image = "dokploy/dokploy:v0.29.5";

    database.passwordFile = "/var/lib/dokploy-secrets/db-password";
    auth.secretFile = "/var/lib/dokploy-secrets/auth-secret";

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
