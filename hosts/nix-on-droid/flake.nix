{
  description = "Advanced example of Nix-on-Droid system config with home-manager.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-on-droid,
    }:
    {

      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./configuration.nix

          # list of extra modules for Nix-on-Droid system
          # { nix.registry.nixpkgs.flake = nixpkgs; }
          # ./path/to/module.nix

          # or import source out-of-tree modules like:
          # flake.nixOnDroidModules.module
        ];

        extraSpecialArgs = {
          # rootPath = ./.;
        };

        pkgs = import nixpkgs {
          system = "aarch64-linux";

          overlays = [
            nix-on-droid.overlays.default
          ];
        };

        home-manager-path = home-manager.outPath;
      };
    };
}
