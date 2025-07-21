# nixos-rebuild switch --flake .#rpi5

{
  description = "Raspberry Pi 5 configuration flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lazyvim = {
      url = "github:matadaniel/LazyVim-module";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # nixConfig = {
  #   extra-substituters = [
  #     "https://nixos-raspberrypi.cachix.org"
  #   ];
  #   extra-trusted-public-keys = [
  #     "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  #   ];
  # };

  outputs =
    {
      self,
      nixpkgs,
      nixos-raspberrypi,
      home-manager,
      stylix,
      ...
    }@inputs:
    {
      nixosConfigurations."rpi5" = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          (
            { ... }:
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.bluetooth
                raspberry-pi-5.display-vc4
                ./pi5-configtext.nix
              ];
            }
          )
          (
            { ... }:
            {
              networking = {
                # Use networkd instead of the pile of shell scripts
                # NOTE: SK: is it safe to combine with NetworkManager on desktops?
                useNetworkd = true;
                hostName = "rpi5";
                networkmanager.enable = true;
                firewall = {
                  # Keep dmesg/journalctl -k output readable by NOT logging
                  # each refused connection on the open internet.
                  logRefusedConnections = false;
                  enable = true;
                  allowedTCPPorts = [
                    # SSH
                    22
                  ];
                  allowedUDPPorts = [
                    # DHCP
                    68
                    546
                  ];
                };
              };

              time.timeZone = "America/Toronto";

              users.users = {
                mfarabi = {
                  initialPassword = "passwd";
                  isNormalUser = true;
                  extraGroups = [
                    "wheel"
                    "networkmanager"
                    "video"
                  ];
                };
                root.initialHashedPassword = "";
              };

              security = {
                polkit.enable = true;
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
              };

              services = {
                openssh = {
                  enable = true;
                  settings.PermitRootLogin = "yes";
                };
                udev.extraRules = ''
                  # Ignore partitions with "Required Partition" GPT partition attribute
                  # On our RPis this is firmware (/boot/firmware) partition
                  ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
                  ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
                  ENV{UDISKS_IGNORE}="1"
                '';
              };

              nix = {
                settings = {
                  auto-optimise-store = true;
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                  trusted-users = [
                    "mfarabi"
                    "root"
                  ];
                  extra-substituters = [
                    "https://cache.nixos.org"
                    "https://nix-community.cachix.org"
                    "https://nixos-raspberrypi.cachix.org"
                  ];
                  extra-trusted-public-keys = [
                    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
                  ];
                };
              };

              systemd = {
                services = {
                  # The notion of "online" is a broken concept
                  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
                  # https://github.com/NixOS/nixpkgs/issues/247608
                  NetworkManager-wait-online.enable = false;
                  # Do not take down the network for too long when upgrading,
                  # This also prevents failures of services that are restarted instead of stopped.
                  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
                  # followed by a delayed `systemctl start`.
                  systemd-networkd.stopIfChanged = false;
                  # Services that are only restarted might be not able to resolve when resolved is stopped before
                  systemd-resolved.stopIfChanged = false;
                };
                network.wait-online.enable = false;
              };

              # We are stateless, so just default to latest.
              system.stateVersion = "25.05";
            }
          )

          (
            { ... }:
            {
              fileSystems = {
                "/boot/firmware" = {
                  device = "/dev/disk/by-uuid/2175-794E";
                  fsType = "vfat";
                  options = [
                    "noatime"
                    "noauto"
                    "x-systemd.automount"
                    "x-systemd.idle-timeout=1min"
                  ];
                };
                "/" = {
                  device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
                  fsType = "ext4";
                  options = [ "noatime" ];
                };
              };
            }
          )
        ];
      };
    };
}
