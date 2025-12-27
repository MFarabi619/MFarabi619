# This is your nixos configuration.
# For home configuration, see /modules/home/*
{
  flake,
  ...
}:
{
  imports = [
    # flake.inputs.self.nixosModules.default
    ./services
    ./security
    ./hardware
    ./programs
    ./networking
    # ./containers

    ./xdg.nix
    ./i18n.nix
    ./time.nix
    ./fonts.nix
    ./console.nix
    ./systemd.nix
    ./myusers.nix
    ./hyprland.nix
    ./environment.nix
    ./virtualisation.nix
  ];
}
