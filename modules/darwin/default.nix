# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{
  imports = [
    ./services

    ./power.nix
    ./system.nix
    ./launchd.nix
    ./security.nix
    ./homebrew.nix
    ./networking.nix
    ./linux-builder.nix

    ../nixos/fonts.nix
    ../nixos/nixpkgs.nix
    ../nixos/myusers.nix
    ../nixos/environment.nix
    ../nixos/documentation.nix
  ];
}
