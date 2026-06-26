{
  pkgs,
  ...
}:
{
  # sudo launchctl list org.nixos.linux-builder
  # sudo cat /etc/nix/builder_ed25519
  # cat /etc/ssh/ssh_config.d/100-linux-builder.conf
  # sudo ssh linux-builder
  nix.linux-builder = {
    maxJobs = 4;
    # enable = pkgs.stdenv.isAarch64;
    enable = false;

    config = {
      imports = [
        ../nixos/time.nix
        ../nixos/i18n.nix
        ../nixos/nixpkgs.nix
      ];

      nix.settings.experimental-features = [
        "flakes"
        "nix-command"
      ];

      virtualisation = {
        cores = 6;
        darwin-builder = {
          diskSize = 40 * 1024;
          memorySize = 8 * 1024;
        };
      };

    };

    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    supportedFeatures = [
      "kvm"
      "benchmark"
      "big-parallel"
    ];
  };
}
