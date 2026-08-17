{
  lib,
  pkgs,
  ...
}:
{
  systemd.user.targets.hyprland-session.Unit.Wants = lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
    "xdg-desktop-autostart.target"
  ];
}
