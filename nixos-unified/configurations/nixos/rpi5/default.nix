# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{
  flake,
  ...
}:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  nixpkgs.hostPlatform = "aarch64-linux";

  imports = [
    self.nixosModules.default
    self.nixosModules.gui

    flake.inputs.lix-module.nixosModules.default

    # flake.inputs.nixos-raspberrypi.nixosModules.default
    flake.inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
    # flake.inputs.nixos-raspberrypi.lib.int.default-nixos-raspberrypi-config

    # flake.inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
    # flake.inputs.nixos-raspberrypi.nixosModules.bootloader
    # flake.inputs.nixos-raspberrypi.nixosModules.usb-gadget-ethernet

    # flake.inputs.nixos-raspberrypi.lib.int.default-nixos-raspberrypi-config

    # flake.inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    # flake.inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
    # flake.inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.bluetooth
    # ./configuration.nix
    # ./pi5-configtext.nix
    {
      nixosConfigurations.default = flake.inputs.nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
          (
            { ... }:
            {
              imports = with flake.inputs.nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.bluetooth
                raspberry-pi-5.display-vc4
                ./pi5-configtext.nix
              ];
            }
          )
          # flake.inputs.home-manager.nixosModules.home-manager
          # {
          #   home-manager = {
          #     useGlobalPkgs = true;
          #     useUserPackages = true;
          #     extraSpecialArgs = {
          #       inherit inputs;
          #     };
          #     users.mfarabi = {
          #       home.stateVersion = "25.05";
          #       imports = [
          #         inputs.lazyvim.homeManagerModules.default
          #         # ./home.nix
          #         # ../nixos/modules/home/services
          #         # ../../modules/home/programs
          #         # ../../modules/home/editorconfig.nix
          #         # ../../modules/home/fonts.nix
          #         # ../../modules/home/manual.nix
          #         # ../../modules/home/shell.nix
          #       ];
          #     };
          #   };
          #   # Optionally, use home-manager.extraSpecialArgs to pass
          #   # arguments to home.nix
          # }
        ];
      };
    }
  ];

}
