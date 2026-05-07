{
  flake,
  ...
}:
{
  imports = [ flake.inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        swap = {
          size = "32G";
          content = {
            type = "swap";
            resumeDevice = true;
            discardPolicy = "both";
          };
        };

        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];

            subvolumes = {
              "@root" = {
                mountpoint = "/";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "discard=async"
                  "space_cache=v2"
                  "compress=zstd:1"
                ];
              };

              "@home" = {
                mountpoint = "/home";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "discard=async"
                  "space_cache=v2"
                  "compress=zstd:1"
                ];
              };

              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "discard=async"
                  "space_cache=v2"
                  "compress=zstd:1"
                ];
              };

              # nodatacow subvolumes — disable copy-on-write for workloads where
              # CoW causes severe fragmentation (random writes to large files).
              # No compression here either; compressing rewriting data is wasted CPU.
              "@postgres" = {
                mountpoint = "/var/lib/postgresql";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "nodatacow"
                  "discard=async"
                ];
              };

              "@docker" = {
                mountpoint = "/var/lib/docker";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "nodatacow"
                  "discard=async"
                ];
              };

              "@libvirt" = {
                mountpoint = "/var/lib/libvirt/images";
                mountOptions = [
                  "ssd"
                  "noatime"
                  "nodatacow"
                  "discard=async"
                ];
              };

              # "@persist" = {
              #   mountpoint = "/persist";
              #   mountOptions = [
              #     "ssd"
              #     "noatime"
              #     "discard=async"
              #     "space_cache=v2"
              #     "compress=zstd:1"
              #   ];
              # };
            };
          };
        };
      };
    };
  };

  # # -----------------------------
  # # PERSIST LAYER INTEGRATION
  # # -----------------------------
  # # Ensure persist base directories exist
  # systemd.tmpfiles.rules = [
  #   "d /persist 0755 root root -"
  #   "d /persist/etc 0755 root root -"
  #   "d /persist/var 0755 root root -"
  #   "d /persist/var/lib 0755 root root -"
  #   "d /persist/var/log 0755 root root -"
  # ];

  # # -----------------------------
  # # MACHINE ID (CRITICAL)
  # # -----------------------------
  # environment.etc."machine-id".source = "/persist/etc/machine-id";

  # # -----------------------------
  # # SSH HOST KEYS (CRITICAL)
  # # -----------------------------
  # services.openssh.hostKeys = [
  #   {
  #     path = "/persist/etc/ssh/ssh_host_ed25519_key";
  #     type = "ed25519";
  #   }
  #   {
  #     path = "/persist/etc/ssh/ssh_host_rsa_key";
  #     type = "rsa";
  #   }
  # ];

  # # -----------------------------
  # # SYSTEM LOG PERSISTENCE
  # # -----------------------------
  # services.journald.extraConfig = ''
  #   Storage=persistent
  # '';

  # environment.etc."nix/persist-base".text = "/persist";
  # services.postgresql.dataDir = "/persist/var/lib/postgresql";
  # systemd.services.docker.serviceConfig.StateDirectory = "/persist/var/lib/docker";
  # systemd.services.tailscaled.serviceConfig.StateDirectory = "/persist/var/lib/tailscale";
}
