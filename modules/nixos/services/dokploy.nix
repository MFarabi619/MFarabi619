{
  pkgs,
  flake,
  config,
  ...
}:
let
  nix-dokploy = builtins.toFile "nix-dokploy.nix" (
    builtins.replaceStrings
      [
        "import ./dokploy-stack.nix"
        "-p 80:80/tcp"
        "-p 443:443/tcp"
        "-p 443:443/udp"
      ]
      [
        "import ${flake.inputs.nix-dokploy}/dokploy-stack.nix"
        "-p 81:80/tcp"
        "-p 444:443/tcp"
        "-p 444:443/udp"
      ]
      (builtins.readFile "${flake.inputs.nix-dokploy}/nix-dokploy.nix")
  );
in
{
  imports = [ (import nix-dokploy) ];

  virtualisation.docker.daemon.settings.live-restore = false;

  services.dokploy = {
    enable = config.networking.hostName == "framework-desktop";
    port = "1212:3000";

    environment.TZ = config.time.timeZone; # docker service update --env-add TZ=America/Toronto dokploy_dokploy
    auth.secretFile = "/var/lib/dokploy-secrets/auth-secret";
    database.passwordFile = "/var/lib/dokploy-secrets/db-password";

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
