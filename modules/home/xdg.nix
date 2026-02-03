{
  lib,
  pkgs,
  config,
  ...
}:
{
  xdg = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;

    configFile."environment.d/envvars.conf".text = ''
      PATH="$HOME/.nix-profile/bin:$PATH"
    '';

    portal = {
      enable = true;
      xdgOpenUsePortal = true;

      extraPortals = with pkgs; [
        # xdg-desktop-portal
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];

      configPackages = with pkgs; [
        xdg-desktop-portal
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    userDirs = {
      enable = true;
      createDirectories = true;

      # Define standard XDG user directories
      music = "${config.home.homeDirectory}/Music";
      videos = "${config.home.homeDirectory}/Videos";
      desktop = "${config.home.homeDirectory}/Desktop";
      pictures = "${config.home.homeDirectory}/Pictures";
      download = "${config.home.homeDirectory}/Downloads";
      publicShare = "${config.home.homeDirectory}/Public";
      documents = "${config.home.homeDirectory}/Documents";
      templates = "${config.home.homeDirectory}/Templates";
    };

    # Define standard XDG base directories
    cacheHome = "${config.home.homeDirectory}/.cache";
    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
  };
}
