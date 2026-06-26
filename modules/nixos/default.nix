# This is your nixos configuration.
# For home configuration, see /modules/home/*
{
  flake,
  ...
}:
{
  imports = [
    ./stylix.nix

    ./services
    ./security
    ./hardware
    ./programs
    ./networking
    # ./containers

    ./nix.nix
    ./xdg.nix
    ./i18n.nix
    ./time.nix
    ./fonts.nix
    ./console.nix
    ./systemd.nix
    ./myusers.nix
    ./environment.nix
    ./virtualisation.nix
  ];
}
