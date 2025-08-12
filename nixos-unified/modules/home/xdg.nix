{
  # config,
  pkgs,
  lib,
  ...
}:
{
  xdg = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;

    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];
      xdgOpenUsePortal = true;
      configPackages = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
        hyprland
      ];
    };

    userDirs = {
      enable = true;
      createDirectories = true;

      # Define standard XDG user directories
      # desktop = "${config.home.homeDirectory}/Desktop";
      # documents = "${config.home.homeDirectory}/Documents";
      # download = "${config.home.homeDirectory}/Downloads";
      # music = "${config.home.homeDirectory}/Music";
      # pictures = "${config.home.homeDirectory}/Pictures";
      # publicShare = "${config.home.homeDirectory}/Public";
      # templates = "${config.home.homeDirectory}/Templates";
      # videos = "${config.home.homeDirectory}/Videos";
    };

    # Define standard XDG base directories
    # cacheHome = "${config.home.homeDirectory}/.cache";
    # configHome = "${config.home.homeDirectory}/.config";
    # dataHome = "${config.home.homeDirectory}/.local/share";
    # stateHome = "${config.home.homeDirectory}/.local/state";
  };
}
