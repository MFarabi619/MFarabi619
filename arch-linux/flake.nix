{
  description = "Arch Linux Nix + Home Manager configuration.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";

    lazyvim.url = "github:pfassina/lazyvim-nix";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-doom-emacs-unstraightened,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      homeConfigurations."mfarabi" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        # extraSpecialArgs = {inherit inputs; };
        modules = [
          inputs.nix-doom-emacs-unstraightened.homeModule
          inputs.lazyvim.homeManagerModules.default
          ./home.nix
        ];
      };
    };
}
