# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{
  imports = [
    ./myusers.nix
    ./documentation.nix
    ./environment.nix
    ./fonts.nix
    ./homebrew.nix
    ./launchd.nix
    ./networking.nix
    ./nixpkgs.nix
    ./power.nix
    ../nixos/fonts.nix
    ./security.nix
    ./services
    ./system.nix
    ./stylix.nix
  ];
}
