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
    flake.inputs.nixos-wsl.nixosModules.default
    flake.inputs.stylix.nixosModules.stylix
    ./configuration.nix
  ];
}
