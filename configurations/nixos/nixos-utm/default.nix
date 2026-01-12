# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    ./configuration.nix
    self.nixosModules.boot
    self.nixosModules.users
    self.nixosModules.default
    flake.inputs.stylix.nixosModules.stylix
    flake.inputs.nix-dokploy.nixosModules.default
  ];
}
