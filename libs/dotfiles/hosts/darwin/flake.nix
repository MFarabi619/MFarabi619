{
  description = "Example nix-darwin system flake";

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
  };

outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }:
    {
      darwinConfigurations."mfarabi" =
        nix-darwin.lib.darwinSystem {
          modules = [
            ./configuration.nix

            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.mfarabi = import ./modules/hm;
            }

          ];
        };

      # Expose the package set, including overlays, for convenience.
      darwinPackages =
        self.darwinConfigurations."mfarabi".pkgs;
    };
}
