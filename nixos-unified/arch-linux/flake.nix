{
  description = "Arch Linux Nix + Home Manager configuration.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "";
    };
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
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."mfarabi" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
                  inputs.nix-doom-emacs-unstraightened.homeModule
          ./home.nix
        ];
      };
    };
}
