{
  # config,
  pkgs,
  lib,
  ...
}:

{

  imports = [
    ./home.nix
    ./rofi.nix
    ./services.nix
    ./systemd.nix
    ./waybar.nix
    ./wayland.nix
  ];
}
