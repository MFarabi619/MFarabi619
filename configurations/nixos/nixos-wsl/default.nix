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
  imports = [
    self.nixosModules.wsl
    self.nixosModules.default
    flake.inputs.stylix.nixosModules.stylix
  ];

  system.stateVersion = "25.05";
  networking.hostName = "nixos-wsl";
  nixos-unified.sshTarget = "nixos-wsl";

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };
}
