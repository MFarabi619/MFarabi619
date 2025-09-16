# git add .; nix run .#update --show-trace
# git add .; nix run .#activate --show-trace
# git add .; nix run .#activate $USER@$HOSTNAME --show-trace
{
  description = "Mumtahin Farabi's distributed NixOS Configurations.";

  # nixConfig = {
  #   extra-substituters = [
  #     "https://nixos-raspberrypi.cachix.org"
  #   ];
  #   extra-trusted-public-keys = [
  #     "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  #   ];
  # };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-unified.url = "github:srid/nixos-unified";
    flake-parts.url = "github:hercules-ci/flake-parts";
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # use fork to allow disabling modules introduced by mkRemovedOptionModule
    # and similar functions
    # see PR nixos:nixpkgs#398456 (https://github.com/NixOS/nixpkgs/pull/398456)
    # nixpkgs-nvmd-modules-with-keys.url = "github:nvmd/nixpkgs/modules-with-keys-25.05";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # inputs.nixpkgs.follows = "nixpkgs-nvmd-modules-with-keys";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixvim = {
    #   url = "github:nix-community/nixvim";
    #   inputs = {
    #     nixpkgs.follows = "nixpkgs";
    #     flake-parts.follows = "flake-parts";
    #   };
    # };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "";
    };

    # vertex.url = "github:juspay/vertex";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    # argononed = {
    #   # url = "git+file:../argononed?shallow=1";
    #   # url = "git+https://gitlab.com/DarkElvenAngel/argononed.git";
    #   url = "github:nvmd/argononed";
    #   flake = false;
    # };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  # nixos-unified.org/autowiring.html
  outputs =
    inputs:
    let
      flake = inputs.nixos-unified.lib.mkFlake {
        inherit inputs;
        root = ./.;
      };
    in
    flake // {
      nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        home-manager-path = inputs.home-manager.outPath;
        extraSpecialArgs = {
          # rootPath = ./.;
          inputs = inputs;
        };

        pkgs = import inputs.nixpkgs {
          system = "aarch64-linux";
          overlays = [
            inputs.nix-on-droid.overlays.default
          ];
        };

        modules = [
          ./modules/nixos/time.nix
          ./configurations/nixos/nix-on-droid/terminal.nix
          ./configurations/nixos/nix-on-droid/environment.nix
          ./configurations/nixos/nix-on-droid/nix-on-droid.nix
          ./configurations/nixos/nix-on-droid/home-manager.nix
          ./configurations/nixos/nix-on-droid/android-integration.nix
        ];
      };
    };
}
