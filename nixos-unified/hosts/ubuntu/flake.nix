{
  description = "Nix-Ubuntu + Home Manager Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
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
    {
      self,
      nixpkgs,
      home-manager,
      system-manager,
      ...
    }@inputs:
    {
      homeConfigurations = {
        mfarabi = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux; # "aarch64-linux"; # for ARM architecture
          extraSpecialArgs = {
            inherit inputs;
          };
          modules = [
            ./modules/hm
          ];
        };
      };
      systemConfigs.default = system-manager.lib.makeSystemConfig {
        modules = [
          ./modules/system
        ];
      };
    };
}
