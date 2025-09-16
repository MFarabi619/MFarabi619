{
  description = "Basic example of Nix-on-Droid system config.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      stylix,
      nix-doom-emacs-unstraightened,
      nix-on-droid,
      ...
    }@inputs:
    {

      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        home-manager-path = home-manager.outPath;
        extraSpecialArgs = {
          # rootPath = ./.;
          inputs = inputs;
        };

        pkgs = import nixpkgs {
          system = "aarch64-linux";
          overlays = [
            nix-on-droid.overlays.default
            # add other overlays
          ];
        };

        modules = [
          # stylix.nixOnDroidModules.stylix
          ./nix-on-droid.nix
          ./environment.nix
          ./android-integration.nix
          ./terminal.nix
          ./home-manager.nix
          ../../../modules/nixos/time.nix
          # ./ssh.nix
        ];

      };

    };
}
