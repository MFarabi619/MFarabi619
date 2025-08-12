# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{
  imports = [
    ./common
    ./documentation.nix
    ./environment.nix
    ./nixpkgs.nix
    ./networking.nix
    ./homebrew.nix
    ./power.nix
    ../nixos/common/fonts.nix
    ./security.nix
    ./services.nix
    ./system.nix
    ./stylix.nix
  ];
}
