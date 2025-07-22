# git add .; nix run .#activate $USER@$HOSTNAME --show-trace
{
  description = "Mumtahin Farabi's distributed NixOS Configurations.";

  inputs = {
    # update with `nix run .#update`
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-index-database = {
      # for comma and command-not-found
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    nixos-unified.url = "github:srid/nixos-unified";

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      lix-module,
      home-manager,
      nix-darwin,
      stylix,
      ...
    }:

    inputs.flake-parts.lib.mkFlake { inherit inputs; } {

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.nixos-unified.flakeModules.default
      ];

      flake =
        let
          myUserName = "mfarabi";
          pkgs = import nixpkgs { system = builtins.currentSystem; };
        in
        {
          legacyPackages.homeConfigurations.${myUserName} = self.nixos-unified.lib.mkHomeConfiguration pkgs (
            { pkgs, ... }:
            {
              imports = [ self.homeModules.default ];
              home = {
                username = myUserName;
                stateVersion = "24.11";
              };
            }
          );

          nixosConfigurations."nixos" = self.nixos-unified.lib.mkLinuxSystem { home-manager = true; } {
            nixpkgs.hostPlatform = "x86_64-linux";
            imports = [
              ./configurations/nixos/flake.nix
              # Setup home-manager in NixOS config
              # {
              #   home-manager.users.${myUserName} = {
              #     imports = [ self.homeModules.default ];
              #     home.stateVersion = "24.11";
              #   };
              # }
            ];
          };

          darwinConfigurations."macos" = self.nixos-unified.lib.mkMacosSystem { home-manager = true; } {
            nixpkgs.hostPlatform = "aarch64-darwin";
            imports = [
              ./configurations/darwin/flake.nix
              # Setup home-manager in nix-darwin config
              # {
              #   home-manager.users.${myUserName} = {
              #     imports = [ self.homeModules.default ];
              #     home.stateVersion = "24.11";
              #   };
              # }
            ];
          };

          homeModules.default =
            { pkgs, ... }:
            {
              imports = [
                ./modules/home/programs
              ];
            };
        };
    };
}
