# machinectl list
# nixos-container list
{
  flake,
  ...
}:
{

  containers.dokploy = {
    privateNetwork = true;
    hostAddress = "192.168.100.10";
    localAddress = "192.168.100.11";

    forwardPorts = [
      {
        hostPort = 1212;
        containerPort = 80;
        protocol = "tcp";
      }
      # {
      #   hostPort = 443;
      #   containerPort = 443;
      #   protocol = "tcp";
      # }
      # {
      #   hostPort = 3000;
      #   containerPort = 3000;
      #   protocol = "tcp";
      # }
    ];

    specialArgs = { inherit flake; };

    config =
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

        virtualisation.docker = {
          enable = true;
          daemon.settings.live-restore = false;
        };

        services.dokploy = {
          enable = true;
          port = "0.0.0.0:80:3000";

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
  };
}
