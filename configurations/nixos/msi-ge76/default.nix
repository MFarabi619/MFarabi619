# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{
  flake,
  config,
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
  networking.hostName = "msi-ge76";
  nixos-unified.sshTarget = config.networking.hostName;

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };
}
