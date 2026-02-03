# git add .; nix run .#update --show-trace
# git add .; nix run .#activate --show-trace
# git add .; nix run .#activate $USER@$HOST --show-trace
{
  description = "Mumtahin Farabi's distributed NixOS Configurations.";

  inputs = {
    nixos-unified.url = "github:srid/nixos-unified";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
    # lix-module.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    lazyvim.url = "github:pfassina/lazyvim-nix";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nixGL.url = "github:guibou/nixGL";
    nixGL.inputs.nixpkgs.follows = "nixpkgs";

    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    # hyprland-plugins.inputs.hyprland.follows = "nixpkgs";

    nix-on-droid.url = "github:nix-community/nix-on-droid/release-24.05";
    nix-on-droid.inputs.nixpkgs.follows = "nixpkgs";
    nix-on-droid.inputs.home-manager.follows = "home-manager";

    # use fork to allow disabling modules introduced by mkRemovedOptionModule and similar functions
    # see PR nixos:nixpkgs#398456 (https://github.com/NixOS/nixpkgs/pull/398456)
    # nixpkgs-nvmd-modules-with-keys.url = "github:nvmd/nixpkgs/modules-with-keys-25.05";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # inputs.nixpkgs.follows = "nixpkgs-nvmd-modules-with-keys";
    };

    # nix-dokploy.url = "github:kedom1337/nix-dokploy/kd/feat/compat";
    nix-dokploy.url = ./nix-dokploy;
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
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
    flake
    // {
      nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        home-manager-path = inputs.home-manager.outPath;
        extraSpecialArgs = {
          # rootPath = ./.;
          inherit inputs;
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
