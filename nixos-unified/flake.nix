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
    # update with `nix run .#update`
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # use fork to allow disabling modules introduced by mkRemovedOptionModule
    # and similar functions
    # see PR nixos:nixpkgs#398456 (https://github.com/NixOS/nixpkgs/pull/398456)
    # nixpkgs-nvmd-modules-with-keys.url = "github:nvmd/nixpkgs/modules-with-keys-25.05";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # inputs.nixpkgs.follows = "nixpkgs-nvmd-modules-with-keys";
    };

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-unified.url = "github:srid/nixos-unified";

    flake-parts.url = "github:hercules-ci/flake-parts";

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

    lazyvim = {
      url = "github:matadaniel/LazyVim-module";
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

    hyprland = {
      url = "github:hyprwm/Hyprland";
    };
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
  };

  # nixos-unified.org/autowiring.html
  outputs =
    inputs:
    inputs.nixos-unified.lib.mkFlake {
      inherit inputs;
      root = ./.;
    };
}
