# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.gui
    flake.inputs.stylix.nixosModules.stylix
    flake.inputs.nixos-wsl.nixosModules.default
    ./configuration.nix
  ];
}
