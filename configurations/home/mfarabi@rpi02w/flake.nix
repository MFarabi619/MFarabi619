{
  description = "Raspberry Pi Zero (DietPi) + Nix + Home Manager configuration.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lazyvim.url = "github:pfassina/lazyvim-nix";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    stylix,
    home-manager,
    ...
  }@inputs:
  let
    system = "aarch64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
    };
  in {
    homeConfigurations."mfarabi" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        inputs.stylix.homeModules.stylix
        inputs.lazyvim.homeManagerModules.default
        ./home.nix
      ];
    };
  };
}
