# List of users for darwin or nixos system and their top-level configuration.
{
  flake,
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (flake.inputs) self;
  mapListToAttrs =
    m: f:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = f name;
      }) m
    );
in
{
  imports = [ ../../modules/shared/nix ];
  options = {
    myusers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of usernames";
      defaultText = "All users under ./configuration/users are included by default";
      default =
        let
          dirContents = builtins.readDir (self + /configurations/home);
          fileNames = builtins.attrNames dirContents; # Extracts keys: [ "mfarabi.nix" ]
          regularFiles = builtins.filter (name: dirContents.${name} == "regular") fileNames; # Filters for regular files
          baseNames = map (name: builtins.replaceStrings [ ".nix" ] [ "" ] name) regularFiles; # Removes .nix extension
        in
        baseNames;
    };
  };

  config = {
    # For home-manager to work.
    # https://github.com/nix-community/home-manager/issues/4026#issuecomment-1565487545
    users.users = mapListToAttrs config.myusers (
      name:
      lib.optionalAttrs pkgs.stdenv.isDarwin {
        home = "/Users/${name}";
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        isNormalUser = true;
      }
    );

    # Enable home-manager for our user
    home-manager.users = mapListToAttrs config.myusers (name: {
      imports = [
        (self + /configurations/home/${name}.nix)
        flake.inputs.nix-doom-emacs-unstraightened.homeModule
        # flake.inputs.nvf.homeManagerModules.default
        flake.inputs.lazyvim.homeManagerModules.default
      ];
    });

    # All users can add Nix caches.
    nix = {
      gc.automatic = true;
      channel.enable = true;
      optimise.automatic = true;

      settings = {
        max-jobs = "auto";

        trusted-users = [
          "@admin"
        ]
        ++ config.myusers;

        experimental-features = [
          "flakes"
          "nix-command"
        ];

        extra-substituters = [
          "https://cache.nixos.org"
          "https://cache.lix.systems"
          "https://devenv.cachix.org"
          "https://nix-community.cachix.org"
        ];

        extra-trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };

      # sudo launchctl list org.nixos.linux-builder
      # sudo cat /etc/nix/builder_ed25519
      # cat /etc/ssh/ssh_config.d/100-linux-builder.conf
      # sudo ssh linux-builder
      linux-builder = {
        maxJobs = 4;
        ephemeral = false;
        enable = pkgs.stdenv.isAarch64;

        config = {
          virtualisation = {
            cores = 6;
            darwin-builder = {
              diskSize = 40 * 1024;
              memorySize = 8 * 1024;
            };
          };

          nix.settings.experimental-features = [
            "flakes"
            "nix-command"
          ];
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
    };
  };
}
