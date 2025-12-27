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

    ./xdg.nix
    ./i18n.nix
    ./time.nix
    ./fonts.nix
    ./console.nix
    # ./containers.nix
    ./systemd.nix
    ./myusers.nix
    ./hyprland.nix
    ./programs.nix
    ./networking.nix
    ./environment.nix
    ./virtualisation.nix
  ];
}
