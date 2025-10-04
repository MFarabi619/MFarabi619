{
  # config,
  pkgs,
  lib,
  ...
}:

{

  imports = [
    ./home.nix
    ./programs.nix
    ./services.nix
    ./systemd.nix
    ./waybar.nix
    ./wayland.nix
  ];
}
