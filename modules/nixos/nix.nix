{
  lib,
  pkgs,
  config,
  ...
}:
{
  # All users can add Nix caches.
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    channel.enable = pkgs.stdenv.isDarwin;
    distributedBuilds = pkgs.stdenv.isDarwin;
    buildMachines = lib.optionals pkgs.stdenv.isDarwin [
      {
        maxJobs = 8;
        sshUser = "mfarabi";
        protocol = "ssh-ng";
        hostName = "framework-desktop";
        sshKey = "/Users/mfarabi/.ssh/id_ed25519";

        systems = [
          "i686-linux"
          "x86_64-linux"
          "aarch64-linux"
        ];

        supportedFeatures = [
          "kvm"
          "benchmark"
          "big-parallel"
        ];
      }
    ];

    settings = rec {
      cores = 0;
      show-trace = true;
      keep-outputs = true;
      trace-verbose = true;
      http-connections = 40;
      keep-derivations = true;
      max-substitution-jobs = 32;
      builders-use-substitutes = true;
      # builders-use-substitutes = pkgs.stdenv.isLinux;
      # FIXME: showing as unknown option despite - https://nix.dev/manual/nix/2.24/command-ref/conf-file.html#conf-download-buffer-size
      # download-buffer-size = 6710886400;
      # download-buffer-size = 17179869184;
      auto-optimise-store = pkgs.stdenv.isLinux;

      experimental-features = [
        "flakes"
        "nix-command"
        "pipe-operators"
      ];

      trusted-users =
        lib.optionals pkgs.stdenv.isLinux [ "root" ]
        ++ lib.optionals pkgs.stdenv.isDarwin [ "@admin" ]
        ++ config.myusers;

      substituters =
        lib.optionals (!(config.services.atticd.enable or false)) [
          "http://framework-desktop:7070/mfarabi"
        ]
        ++ [
          "https://cache.nixos.org"
          "https://cachix.cachix.org"
          "https://devenv.cachix.org"
          "https://nixpkgs.cachix.org"
          "https://nix-community.cachix.org"
          "https://doom-emacs-unstraightened.cachix.org"
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [ "https://nix-darwin.cachix.org" ];

      trusted-substituters =
        substituters
        ++ lib.optionals (config.services.proxmox-ve.enable or false) [
          "https://cache.saumon.network/proxmox-nixos"
        ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4="
      ]
      ++ lib.optionals (!(config.services.atticd.enable or false)) [
        "mfarabi:9j4mW1ebyKidbRB59Wjxer85IyggTyl0/nPRF2W3M7Y="
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
      ]
      ++ lib.optionals (config.services.proxmox-ve.enable or false) [
        "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
      ];

      extra-substituters = [
        "https://emacs-ci.cachix.org"
      ]
      ++ lib.optionals (config.programs.hyprland.enable or false) [
        "https://hyprland.cachix.org"
      ];

      extra-trusted-public-keys = [
        "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
      ]
      ++ lib.optionals (config.programs.hyprland.enable or false) [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };
  };
}
