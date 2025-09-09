{ config, lib, ... }:

let
  firmwarePartition = lib.recursiveUpdate {
    priority = 1;
    type = "0700"; # Microsoft basic data
    size = "1024M";
    label = "FIRMWARE";
    attributes = [
      0 # Required Partition
    ];
    content = {
      format = "vfat";
      type = "filesystem";
      # mountpoint = "/boot/firmware";
      mountOptions = [
        "noauto"
        "noatime"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    type = "EF00"; # EFI System Partition (ESP)
    label = "ESP";
    size = "1024M";
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];
    content = {
      format = "vfat";
      type = "filesystem";
      # mountpoint = "/boot";
      mountOptions = [
        "noauto"
        "noatime"
        "umask=0077"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

in
{

  # https://nixos.wiki/wiki/Btrfs#Scrubbing
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  fileSystems = {
    "/var/log".neededForBoot = true; # mount early enough in the boot process so no logs will be lost
  };

  disko.devices.disk.main = {
    type = "disk";
    # device = "/dev/sda";
    device = "/dev/nvme0n1";
    # device = "/dev/mmcblk0";

    content = {
      type = "gpt";
      partitions = {
        FIRMWARE = firmwarePartition {
          label = "FIRMWARE";
          content.mountpoint = "/boot/firmware";
        };

        ESP = espPartition {
          label = "ESP";
          content.mountpoint = "/boot";
        };

        system = {
          size = "100%";
          type = "8305"; # Linux ARM64 root (/)
          content = {
            type = "btrfs";
            extraArgs = [
              "--label nixos"
              "-f" # Override existing partition
            ];
            postCreateHook =
              let
                thisBtrfs = config.disko.devices.disk.main.content.partitions.system.content;
                device = thisBtrfs.device;
                subvolumes = thisBtrfs.subvolumes;

                makeBlankSnapshot =
                  btrfsMntPoint: subvol:
                  let
                    subvolAbsPath = lib.strings.normalizePath "${btrfsMntPoint}/${subvol.name}";
                    dst = "${subvolAbsPath}-blank";
                    # NOTE: this one-liner has the same functionality (inspired by zfs hook)
                    # btrfs subvolume list -s mnt/rootfs | grep -E ' rootfs-blank$' || btrfs subvolume snapshot -r mnt/rootfs mnt/rootfs-blank
                  in
                  ''
                    if ! btrfs subvolume show "${dst}" > /dev/null 2>&1; then
                      btrfs subvolume snapshot -r "${subvolAbsPath}" "${dst}"
                    fi
                  '';
                # Mount top-level subvolume (/) with "subvol=/", without it
                # the default subvolume will be mounted. They're the same in
                # this case, though. So "subvol=/" isn't really necessary
              in
              ''
                MNTPOINT=$(mktemp -d)
                mount ${device} "$MNTPOINT" -o subvol=/
                trap 'umount $MNTPOINT; rm -rf $MNTPOINT' EXIT
                ${makeBlankSnapshot "$MNTPOINT" subvolumes."/rootfs"}
              '';
            subvolumes = {
              "/rootfs" = {
                mountpoint = "/";
                mountOptions = [ "noatime" ];
              };
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [ "noatime" ];
              };
              "/home" = {
                mountpoint = "/home";
                mountOptions = [ "noatime" ];
              };
              "/log" = {
                mountpoint = "/var/log";
                mountOptions = [ "noatime" ];
              };
              "/swap" = {
                mountpoint = "/.swapvol";
                swap."swapfile" = {
                  size = "8G";
                  priority = 3; # (higher number -> higher priority)
                  # to be used after zswap (set zramSwap.priority > this priority),
                  # but before "hibernation" swap
                  # https://github.com/nix-community/disko/issues/651
                };
              };
            };
          };
        }; # system

        swap = {
          size = "17G"; # RAM + 1GB
          type = "8200"; # Linux swap
          content = {
            type = "swap";
            resumeDevice = true; # "hibernation" swap
            # zram's swap will be used first, and this one only
            # used when the system is under pressure enough that zram and
            # "regular" swap above didn't work
            # https://github.com/systemd/systemd/issues/16708#issuecomment-1632592375
            # (set zramSwap.priority > btrfs' .swapvol priority > this priority)
            priority = 2;
          };
        };

      };
    };
  }; # disko.devices.disk.main
}
