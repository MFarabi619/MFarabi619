# This is your nixos configuration.
# For home configuration, see /modules/home/*
{
  flake,
  ...
}:
{
  imports = [
    # flake.inputs.stylix.nixosModules.stylix

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
    ./hyprland.nix
    ./environment.nix
    ./documentation.nix
    ./virtualisation.nix
  ];
}
