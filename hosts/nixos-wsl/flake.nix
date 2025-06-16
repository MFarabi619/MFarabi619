{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
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

  outputs = { self, nixpkgs, nixos-wsl, home-manager, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          {
            system.stateVersion = "24.11";

            wsl = {
              enable = true;
              defaultUser = "mfarabi";
              docker-desktop.enable = true;
              startMenuLaunchers = true;
              # tarball.configPath = null;
              usbip = {
                enable = true;
                autoAttach = [ ];
                };
              useWindowsDriver = true;
              wslConf = {
                boot = {
                  command = "echo 'Hello from NixOS-WSL 👋'";
                };
              };
            };


            # environment.systemPackages = [
            #     nixpkgs.pkgs.wget
            # ];

            # programs.nix-ld = {
            #     enable = true;
            #     package = nixpkgs.pkgs.nix-ld-rs; # only for NixOS 24.05
            # };
          }
        ];
    };
    #  homeConfigurations = {
    #   mfarabi = home-manager.lib.homeManagerConfiguration {
    #     pkgs = nixpkgs.legacyPackages.x86_64-linux; # "aarch64-linux"; # for ARM architecture
    #        extraSpecialArgs = {
    #       inherit inputs;
    #     };
    #     modules = [
    #       ../ubuntu/modules/hm
    #     ];
    #   };
    # };
    #
    # environment.pathsToLink = [
    #   "/share/zsh"
    #   "/share/bash-completion"
    # ];
  };
}


