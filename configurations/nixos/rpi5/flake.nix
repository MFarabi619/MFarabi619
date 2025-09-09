{
  description = "Raspberry Pi 5 configuration flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
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

    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
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
      hyprland,
      hyprland-plugins,
      nix-doom-emacs-unstraightened,
      nix-index-database,
      ...
    }@inputs:
    {
      nixosConfigurations."rpi5" = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          # lix-module.nixosModules.default
          stylix.nixosModules.stylix
          ./configuration.nix
          {
            imports = with inputs.nixos-raspberrypi.nixosModules; [
              trusted-nix-caches
              usb-gadget-ethernet
              raspberry-pi-5.base
              raspberry-pi-5.bluetooth
              raspberry-pi-5.display-vc4
              # nixpkgs-rpi
              ./pi5-configtxt.nix
            ];
          }
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit inputs;
              };
              users.mfarabi = {
                home.stateVersion = "25.05";
                imports = [
                  inputs.nix-doom-emacs-unstraightened.homeModule
                  stylix.homeModules.stylix
                  ../../../modules/home/programs
                  ../../../modules/home/services
                  ../../../modules/home/targets
                  ../../../modules/home/editorconfig.nix
                  ../../../modules/home/fonts.nix
                  ../../../modules/home/home.nix
                  ../../../modules/home/manual.nix
                  ../../../modules/home/packages.nix
                  # ../../../modules/home/nix-index.nix
                  ../../../modules/home/stylix.nix
                  ../../../modules/home/xdg.nix
                ];
              };
            };
            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
        ];
      };
    };
}
