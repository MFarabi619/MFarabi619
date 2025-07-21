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
  };

  outputs =
    inputs@{ self, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      imports = [
        inputs.nixos-unified.flakeModules.default
      ];

      perSystem =
        { pkgs, ... }:
        let
          myUserName = "mfarabi";
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
        };

      flake = {
        homeModules.default =
          { pkgs, ... }:
          {
            imports = [
              ./modules/hm/programs
            ];

          };
      };
    };
}
