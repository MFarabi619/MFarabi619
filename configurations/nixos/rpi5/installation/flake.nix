{
  description = ''
    Examples of NixOS systems' configuration for Raspberry Pi boards
    using nixos-raspberrypi
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    disko = {
      # url = "github:nix-community/disko";
      url = "github:nvmd/disko/gpt-attrs"; # fork needed for partition attributes support
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  };

  nixConfig = {
    # bash-prompt = "\[nixos-raspberrypi-demo\] ➜ ";
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixos-anywhere,
      nixos-raspberrypi,
      ...
    }@inputs:
    let
      allSystems = nixpkgs.lib.systems.flakeExposed;
      forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {

      devShells = forSystems allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              nil
              nixpkgs-fmt
              nix-output-monitor
              nixos-anywhere.packages.${system}.default
            ];
          };
        }
      );

      nixosConfigurations =
        let
          users-config-stub = (
            { config, ... }:
            {
              # This is identical to what nixos installer does in
              # (modulesPash + "profiles/installation-device.nix")

              # Use less privileged user
              users.users = {
                nixos = {
                  isNormalUser = true;
                  extraGroups = [
                    "wheel"
                    "networkmanager"
                    "video"
                  ];
                  initialHashedPassword = ""; # Allow graphical user login without password
                };
                root.initialHashedPassword = ""; # Allow user to log in as root without password.
              };

              security = {
                polkit.enable = true; # Don't require sudo/root to `reboot` or `poweroff`
                # Allow passwordless sudo from user
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
              };

              services = {
                getty.autologinUser = "nixos";
                # We run sshd by default. Login is only possible after adding a
                # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
                # The latter one is particular useful if keys are manually added to
                # installation device for head-less systems i.e. arm boards by manually
                # mounting the storage in a different system.
                openssh = {
                  enable = true;
                  settings.PermitRootLogin = "yes";
                };
              };

              # allow nix-copy to live system
              nix = {
                settings = {
                  max-jobs = "auto";
                  trusted-users = [
                    "nixos"
                    "mfarabi"
                    "root"
                  ];
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                  substituters = [
                    "https://cache.nixos.org"
                    "https://cache.lix.systems"
                    "https://nix-community.cachix.org"

                    "https://nixpkgs.cachix.org"
                    "https://cachix.cachix.org"
                    "https://devenv.cachix.org"

                    "https://nix-darwin.cachix.org"
                    "https://nix-on-droid.cachix.org"
                    "https://nixos-raspberrypi.cachix.org"

                    "https://mfarabi.cachix.org"
                    "https://fuellabs.cachix.org"
                    "https://charthouse-labs.cachix.org"

                    "https://emacsng.cachix.org"
                    "https://emacs-ci.cachix.org"
                    "https://nixvim.cachix.org"

                    "https://hyprland.cachix.org"
                  ];

                  trusted-substituters = [
                    "https://cache.nixos.org"
                    "https://cache.lix.systems"
                    "https://nix-community.cachix.org"

                    "https://nixpkgs.cachix.org"
                    "https://cachix.cachix.org"
                    "https://devenv.cachix.org"

                    "https://nix-darwin.cachix.org"
                    "https://nixos-raspberrypi.cachix.org"

                    "https://charthouse-labs.cachix.org"
                    "https://mfarabi.cachix.org"
                    "https://fuellabs.cachix.org"

                    "https://emacs-ci.cachix.org"
                    "https://nixvim.cachix.org"

                    "https://hyprland.cachix.org"
                  ];

                  trusted-public-keys = [
                    "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
                    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
                    "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
                    "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
                    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
                    "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
                    "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
                    "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
                    "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
                    "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
                    "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
                    "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
                    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
                  ];

                  extra-substituters = [

                    "https://cache.nixos.org"
                    "https://cache.lix.systems"
                    "https://nix-community.cachix.org"

                    "https://nixpkgs.cachix.org"
                    "https://cachix.cachix.org"
                    "https://devenv.cachix.org"

                    "https://nix-darwin.cachix.org"
                    "https://nixos-raspberrypi.cachix.org"

                    "https://charthouse-labs.cachix.org"
                    "https://mfarabi.cachix.org"
                    "https://fuellabs.cachix.org"

                    "https://emacs-ci.cachix.org"
                    "https://nixvim.cachix.org"

                    "https://hyprland.cachix.org"
                  ];

                  extra-trusted-public-keys = [
                    "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
                    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
                    "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
                    "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
                    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
                    "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
                    "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
                    "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
                    "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
                    "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
                    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
                  ];
                };
              };

              system.stateVersion = config.system.nixos.release; # we're stateless, so default to latest.
            }
          );

          network-config = {
            # mostly portions of safe network configuration defaults from nixos-images & srvos
            networking = {
              useNetworkd = true;
              firewall.allowedUDPPorts = [ 5353 ];
              # Use iwd instead of wpa_supplicant. It has a user friendly CLI
              wireless = {
                enable = false;
                iwd = {
                  enable = true;
                  settings = {
                    Network = {
                      EnableIPv6 = true;
                      RoutePriorityOffset = 300;
                    };
                    Settings.AutoConnect = true;
                  };
                };
              };
            };
            # mdns
            systemd = {
              network.networks = {
                "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
                "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
              };
              # This comment was lifted from `srvos`
              # Do not take down the network for too long when upgrading,
              # This also prevents failures of services that are restarted instead of stopped.
              # It will use `systemctl restart` rather than stopping it with `systemctl stop`
              # followed by a delayed `systemctl start`.
              services = {
                systemd-networkd.stopIfChanged = false;
                # Services that are only restarted might be not able to resolve when resolved is stopped before
                systemd-resolved.stopIfChanged = false;
              };
            };
          };

          common-user-config =
            { config, pkgs, ... }:
            {
              imports = [
                ./nice-looking-console.nix
                users-config-stub
                network-config
              ];

              time.timeZone = "America/Toronto";
              # networking.hostName = "rpi${config.boot.loader.raspberryPi.variant}-demo";
              networking.hostName = "rpi5";

              services.udev.extraRules = ''
                # Ignore partitions with "Required Partition" GPT partition attribute
                # On our RPis this is firmware (/boot/firmware) partition
                ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
                  ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
                  ENV{UDISKS_IGNORE}="1"
              '';

              environment.systemPackages = with pkgs; [
                tree
                # raspberrypi-eeprom
              ];

              users.users = {
                nixos.openssh.authorizedKeys.keys = [
                  # YOUR SSH PUB KEY HERE #
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM"
                ];
                root.openssh.authorizedKeys.keys = [
                  # YOUR SSH PUB KEY HERE #
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM"
                ];
              };

              system.nixos.tags =
                let
                  cfg = config.boot.loader.raspberryPi;
                in
                [
                  "raspberry-pi-${cfg.variant}"
                  cfg.bootloader
                  config.boot.kernelPackages.kernel.version
                ];
            };
        in
        {
          rpi4 = nixos-raspberrypi.lib.nixosSystem {
            specialArgs = inputs;
            modules = [
              (
                {
                  lib,
                  pkgs,
                  config,
                  disko,
                  nixos-raspberrypi,
                  ...
                }:
                {
                  imports = with nixos-raspberrypi.nixosModules; [
                    raspberry-pi-4.base
                    raspberry-pi-4.bluetooth
                    raspberry-pi-4.display-vc4
                  ];
                }
              )
              disko.nixosModules.disko
              # WARNING: formatting disk with disko is DESTRUCTIVE, check `disko.devices.disk.main.device` is set correctly!
              ./disko-usb-btrfs.nix
              common-user-config
              {
                boot.tmp.useTmpfs = true;
              }
            ];
          };

          rpi5 = nixos-raspberrypi.lib.nixosSystemFull {
            specialArgs = inputs;
            modules = [
              (
                {
                  lib,
                  pkgs,
                  disko,
                  config,
                  nixos-raspberrypi,
                  ...
                }:
                {
                  imports = with nixos-raspberrypi.nixosModules; [
                    trusted-nix-caches
                    usb-gadget-ethernet
                    raspberry-pi-5.base
                    raspberry-pi-5.bluetooth
                    raspberry-pi-5.display-vc4
                    ./pi5-configtxt.nix
                  ];
                }
              )
              disko.nixosModules.disko
              # WARNING: formatting disk with disko is DESTRUCTIVE, check if
              # `disko.devices.disk.nvme0.device` is set correctly!
              # ./disko-nvme-zfs.nix
              # { networking.hostId = "8821e309"; } # NOTE: for zfs, must be unique
              # WARNING: formatting disk with disko is DESTRUCTIVE, check if
              # `disko.devices.disk.main.device` is set correctly!
              ./disko-usb-btrfs.nix
              common-user-config
              {
                boot = {
                  tmp.useTmpfs = true;
                  loader = {
                    raspberryPi = {
                      enable = true;
                      # bootloader = "kernel";
                    };
                  };
                };
              }

              # Advanced: Use non-default kernel from kernel-firmware bundle
              # ({ config, pkgs, lib, ... }: let
              #   kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
              # in {
              #   boot = {
              #     loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
              #     kernelPackages = kernelBundle.linuxPackages_rpi5;
              #   };

              #   nixpkgs.overlays = lib.mkAfter [
              #     (self: super: {
              #       # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least
              #       # enableRedistributableFirmware is enabled
              #       # I know no easier way to override this package
              #       inherit (kernelBundle) raspberrypiWirelessFirmware;
              #       # Some derivations want to use it as an input,
              #       # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
              #       inherit (kernelBundle) raspberrypifw;
              #     })
              #   ];
              # })
            ];
          };
        };
    };
}
