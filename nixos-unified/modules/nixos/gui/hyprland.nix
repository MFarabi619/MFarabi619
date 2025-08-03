{pkgs, inputs, ...}:

{

  programs = {
    uwsm.enable = true;
    hyprland = {
      enable = true;
      # package = inputs.hyprland.packages."${pkgs.system}".hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };
    nix-ld.enable = true;
    dconf.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    hyprlock = {
      enable = true;
    };
  };

  environment = {
    variables = {
      NIXOS_OZONE_WL = "1";
    };

    pathsToLink = [
      "/share/icons"
      "/share/themes"
      "/share/fonts"
      "/share/xdg-desktop-portal"
      "/share/applications"
      "/share/mime"
      "/share/wayland-sessions"
      "/share/zsh"
      "/share/bash-completion"
      "/share/fish"
    ];
    systemPackages = with pkgs; [
      kitty
    ];
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };

  xdg = {
    # enable = true;
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
      ];
    };
    # mimeApps.enable = true;

    # userDirs = {
      #   enable = true;
      #   createDirectories = true;
      # };
  };

  services = {
    # xserver.enable = true;
    # hyprlock.enable = true;
  };
}
