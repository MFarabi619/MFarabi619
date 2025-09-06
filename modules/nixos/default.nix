# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, ... }:
{
  imports = [
    # flake.inputs.self.nixosModules.default
    ./services
    ./console.nix
    ./environment.nix
    ./fonts.nix
    ./hardware.nix
    ./hyprland.nix
    ./i18n.nix
    ./myusers.nix
    ./networking.nix
    ./nix.nix
    ./programs.nix
    ./security.nix
    ./systemd.nix
    ./time.nix
    ./virtualisation.nix
    ./xdg.nix
  ];
}
