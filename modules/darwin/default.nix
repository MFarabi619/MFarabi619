# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{
  imports = [
    ./services

    ./power.nix
    ./fonts.nix
    ./system.nix
    ./stylix.nix
    ./nixpkgs.nix
    ./launchd.nix
    ./security.nix
    ./homebrew.nix
    ./networking.nix
    ./environment.nix
    ./documentation.nix
    ./linux-builder.nix

    ../nixos/fonts.nix
    ../nixos/myusers.nix
  ];
}
