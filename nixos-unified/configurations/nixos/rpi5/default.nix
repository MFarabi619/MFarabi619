# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    flake.inputs.lix-module.nixosModules.default
    flake.inputs.stylix.nixosModules.stylix
    self.nixosModules.default
    self.nixosModules.gui
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
  ];
}
