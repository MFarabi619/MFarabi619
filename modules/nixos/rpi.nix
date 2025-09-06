
# # This is your nixos configuration.
# # For home configuration, see /modules/home/*
# { flake, inputs, ... }:
# {
#   imports = [
#       flake.inputs.nixos-raspberrypi.lib.nixosSystem {
#         specialArgs = inputs;
#         modules = [
#           {
#             imports = with flake.inputs.nixos-raspberrypi.nixosModules; [
#               default
#               trusted-nix-caches
#               bootloader
#               usb-gadget-ethernet
#               raspberry-pi-5.base
#               raspberry-pi-5.display-vc4
#               raspberry-pi-5.bluetooth
#               # lib.int.default-nixos-raspberrypi-config
#               nixpkgs-rpi
#               ./pi5-configtext.nix
#             ];
#           }
#           (
#             {
#               config,
#               pkgs,
#               lib,
#               ...
#             }:
#             {
#               # system.nixos.tags =
#               #   let
#               #     cfg = config.boot.loader.raspberryPi;
#               #   in
#               #   [
#               #     "raspberry-pi-${cfg.variant}"
#               #     cfg.bootloader
#               #     config.boot.kernelPackages.kernel.version
#               #   ];

#               networking = {
#                 hostName = "rpi5";
#                 # Use networkd instead of the pile of shell scripts
#                 # NOTE: SK: is it safe to combine with NetworkManager on desktops?
#                 useNetworkd = true;
#                 # Keep dmesg/journalctl -k output readable by NOT logging
#                 # each refused connection on the open internet.
#                 firewall.logRefusedConnections = false;
#               };

#               systemd = {
#                 network.wait-online.enable = false;
#                 services = {
#                   # The notion of "online" is a broken concept
#                   # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
#                   # https://github.com/NixOS/nixpkgs/issues/247608
#                   NetworkManager-wait-online.enable = false;
#                   # Do not take down the network for too long when upgrading,
#                   # This also prevents failures of services that are restarted instead of stopped.
#                   # It will use `systemctl restart` rather than stopping it with `systemctl stop`
#                   # followed by a delayed `systemctl start`.
#                   systemd-networkd.stopIfChanged = false;
#                   # Services that are only restarted might be not able to resolve when resolved is stopped before
#                   systemd-resolved.stopIfChanged = false;
#                 };
#               };

#               services.udev.extraRules = ''
#                 # Ignore partitions with "Required Partition" GPT partition attribute
#                 # On our RPis this is firmware (/boot/firmware) partition
#                 ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
#                 ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
#                 ENV{UDISKS_IGNORE}="1"
#               '';
#               fileSystems = {
#                 "/boot/firmware" = {
#                   device = "/dev/disk/by-uuid/2175-794E";
#                   fsType = "vfat";
#                   options = [
#                     "noatime"
#                     "noauto"
#                     "x-systemd.automount"
#                     "x-systemd.idle-timeout=1min"
#                   ];
#                 };
#                 "/" = {
#                   device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
#                   fsType = "ext4";
#                   options = [ "noatime" ];
#                 };
#               };

#             }
#           )
#         ];
#       };
#   ];
# }
