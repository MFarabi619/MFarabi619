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
        shell = pkgs.zsh;

        extraGroups = [
          "dialout"
        ];
      }
    );

    home-manager = {
      backupFileExtension = "hm-bak";
      users = mapListToAttrs config.myusers (name: {
        imports = [
          (self + /configurations/home/${name}.nix)
          flake.inputs.lazyvim.homeManagerModules.default
          flake.inputs.nix-doom-emacs-unstraightened.homeModule
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          flake.inputs.stylix.homeModules.stylix
        ];
      });
    };

    # All users can add Nix caches.
    nix = {
      channel.enable = pkgs.stdenv.isDarwin;
      # builders-use-substitutes = pkgs.stdenv.isLinux;

      optimise = {
        automatic = true;
        # dates = "daily";
        # persistent = true;
      };

      gc = {
        automatic = true;
        # persistent = true;
        # dates = "daily";
        # options = "";
      };

      settings = {
        max-jobs = "auto";
        show-trace = true;
        trace-verbose = true;
        http-connections = 40;
        max-substitution-jobs = 32;
        # FIXME: showing as unknown option despite - https://nix.dev/manual/nix/2.24/command-ref/conf-file.html#conf-download-buffer-size
        # download-buffer-size = 6710886400;
        auto-optimise-store = pkgs.stdenv.isLinux;

        experimental-features = [
          "flakes"
          "nix-command"
        ];

        trusted-users = [
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          "root"
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          "@admin"
        ]
        ++ config.myusers;

        substituters = [
          "https://cache.nixos.org"
          "https://cache.lix.systems"
          "https://cachix.cachix.org"
          "https://devenv.cachix.org"
          "https://mfarabi.cachix.org"
          "https://nixpkgs.cachix.org"
          "https://nix-darwin.cachix.org"
          "https://nix-community.cachix.org"
        ];

        trusted-substituters = [
          "https://cache.nixos.org"
          "https://cache.lix.systems"
          "https://cachix.cachix.org"
          "https://devenv.cachix.org"
          "https://mfarabi.cachix.org"
          "https://nixpkgs.cachix.org"
          "https://nix-darwin.cachix.org"
          "https://nix-community.cachix.org"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
          "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
          "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
          "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];

        extra-substituters = [
          "https://emacs-ci.cachix.org"
          "https://hyprland.cachix.org"
          "https://nix-on-droid.cachix.org"
          "https://nixos-raspberrypi.cachix.org"
        ];

        extra-trusted-public-keys = [
          "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
          "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        ];
      };
    };
  };
}
