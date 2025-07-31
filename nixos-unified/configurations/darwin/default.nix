# See /modules/darwin/* for actual settings
# This file is just *top-level* configuration.
{ flake, lib, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.darwinModules.default
    inputs.lix-module.nixosModules.default
    inputs.stylix.darwinModules.stylix
  ];

  nixpkgs = {
    # buildPlatform = "aarch64-darwin";
    hostPlatform = "aarch64-darwin";
    config = {
      allowUnfree = true;
    };
  };

  networking = {
    computerName = "macos";
    hostName = "macos";
    localHostName = "macos";
    wakeOnLan.enable = true;
  };

  system.primaryUser = "mfarabi";

  # Automatically move old dotfiles out of the way
  #
  # Note that home-manager is not very smart, if this backup file already exists it
  # will complain "Existing file .. would be clobbered by backing up". To mitigate this,
  # we try to use as unique a backup file extension as possible.
  home-manager.backupFileExtension = "nixos-unified-template-backup";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;
}
