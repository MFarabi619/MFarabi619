{
  description = "nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
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

  outputs = inputs@{
    self,
    nix-darwin,
    nixpkgs,
    home-manager,
    stylix,
      ...
  }: {
    darwinConfigurations."mfarabi" = nix-darwin.lib.darwinSystem {
      modules = [
        stylix.darwinModules.stylix
        ./configuration.nix

        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
            };
            users.mfarabi = import ./modules/hm;
          };
        }
      ];
    };

    darwinPackages = self.darwinConfigurations."mfarabi".pkgs;
  };
}
