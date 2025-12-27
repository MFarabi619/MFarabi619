{
  lib,
  pkgs,
  config,
  ...
}:
{
  xdg = {
    icons.enable = true;
    autostart.enable = true;

    portal = lib.mkIf config.programs.xwayland.enable {
      enable = true;
      wlr.enable = true;
      xdgOpenUsePortal = true;

      extraPortals =
        with pkgs;
        [
          xdg-desktop-portal
          xdg-desktop-portal-gtk
        ]
        ++ lib.optionals config.programs.hyprland.enable [
          xdg-desktop-portal-hyprland
        ];

      configPackages =
        with pkgs;
        [
          xdg-desktop-portal
          xdg-desktop-portal-gtk
        ]
        ++ lib.optionals config.programs.hyprland.enable [
          xdg-desktop-portal-hyprland
        ];
    };
  };
}
