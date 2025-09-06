# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{
  imports = [
    ./myusers.nix
    ./documentation.nix
    ./environment.nix
    ./homebrew.nix
    ./networking.nix
    ./nixpkgs.nix
    ./power.nix
    ../nixos/common/fonts.nix
    ./security.nix
    ./services
    ./system.nix
    ./stylix.nix
  ];
}
