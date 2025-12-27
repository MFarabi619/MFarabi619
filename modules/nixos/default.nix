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

    ./console.nix
    # ./containers.nix
    ./environment.nix
    ./fonts.nix
    ./hyprland.nix
    ./i18n.nix
    ./myusers.nix
    ./networking.nix
    ./programs.nix
    ./systemd.nix
    ./time.nix
    ./virtualisation.nix
    ./xdg.nix
  ];
}
