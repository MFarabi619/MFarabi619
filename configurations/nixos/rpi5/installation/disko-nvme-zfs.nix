{ config, lib, ... }:

let
  firmwarePartition = lib.recursiveUpdate {
    label = "FIRMWARE";
    priority = 1;
    type = "0700"; # Microsoft basic data
    size = "1024M";
    attributes = [
      0 # Required Partition
    ];
    content = {
      format = "vfat";
      type = "filesystem";
      # mountpoint = "/boot/firmware";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    label = "ESP";
    type = "EF00"; # EFI System Partition (ESP)
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

  boot.supportedFilesystems = [ "zfs" ];
  # networking.hostId is set somewhere else
  services.zfs = {
    trim.enable = true;
    autoScrub.enable = true;
  };

  disko.devices = {
    disk.nvme0 = {
      type = "disk";
      device = "/dev/nvme0n1";
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

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool"; # zroot
            };
          };

        };
      };
    }; # nvme0

    zpool = {
      rpool = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on"; # see also services.zfs.trim.enable
        };

        rootFsOptions = {
          # zfs properties
          # "com.sun:auto-snapshot" = "false";
          # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
          xattr = "sa";
          atime = "off";
          canmount = "off";
          dnodesize = "auto";
          compression = "lz4";
          mountpoint = "none";
          acltype = "posixacl";
          # https://rubenerd.com/forgetting-to-set-utf-normalisation-on-a-zfs-pool/
          normalization = "formD";
        };

        postCreateHook =
          let
            poolName = "rpool";
          in
          "zfs list -t snapshot -H -o name | grep -E '^${poolName}@blank$' || zfs snapshot ${poolName}@blank";

        datasets = {
          # stuff which can be recomputed/easily redownloaded, e.g. nix store
          local = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix"; # nixos configuration mountpoint
            options = {
              reservation = "128M";
              mountpoint = "legacy"; # to manage "with traditional tools"
            };
          };

          # _system_ data
          system = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "system/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          "system/var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options.mountpoint = "legacy";
          };

          # _user_ and _user service_ data. safest, long retention policy
          safe = {
            type = "zfs_fs";
            options = {
              copies = "2";
              mountpoint = "none";
            };
          };
          "safe/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
          "safe/var/lib" = {
            type = "zfs_fs";
            mountpoint = "/var/lib";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
