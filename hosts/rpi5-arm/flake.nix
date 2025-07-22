{
  description = "Raspberry Pi 5 configuration flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.1.tar.gz";
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
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-raspberrypi,
      lix-module,
      home-manager,
      stylix,
      ...
    }@inputs:
    {
      nixosConfigurations."rpi5" = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          lix-module.nixosModules.default
          stylix.nixosModules.stylix
          ./configuration.nix
          ./hardware-configuration.nix
          (
            { ... }:
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.bluetooth
                raspberry-pi-5.display-vc4
                ./pi5-configtext.nix
              ];
            }
          )
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit inputs;
              };
              users.mfarabi = {
                imports = [
                  ../../hosts/darwin/modules/hm/programs.nix
                  ../../modules/hm/programs
                  # ../../modules/hm/stylix.nix
                  ../../modules/hm/manual.nix
                ];

                home = {
                  username = "mfarabi";
                  stateVersion = "25.05";

                  shell = {
                    enableShellIntegration = true;
                    enableBashIntegration = true;
                    enableZshIntegration = true;
                  };

                  language = {
                    base = "en_US";
                  };
                };
              };
            };
            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
        ];
      };
    };
}
