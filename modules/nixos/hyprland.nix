{ pkgs, inputs, ... }:

{
  programs = {
    xwayland.enable = true;
    hyprlock.enable = true;
    uwsm = {
      enable = true;
      # waylandCompositors = {
      #     prettyName = "Hyprland";
      #     comment = "Hyprland compositor managed by UWSM";
      #     binPath = "/run/current-system/sw/bin/hyprland";
      # };
    };
    hyprland = {
      enable = true;
      # package = inputs.hyprland.packages."${pkgs.system}".hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };
    dconf = {
      enable = true;
      # settings = {
      #   "org/virt-manager/virt-manager/connections" = {
      #     autoconnect = [ "qemu:///system" ];
      #     uris = [ "qemu:///system" ];
      #   };
      # };
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  environment = {
    variables.NIXOS_OZONE_WL = "1";
    sessionVariables.NIXOS_OZONE_WL = "1";

    systemPackages = with pkgs; [ kitty ];

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
  };

  services = {
    getty.autologinUser = "mfarabi";
    displayManager = {
      sddm = {
        enable = false;
        # settings = {

        # };
        wayland = {
          enable = true;
          # compositor = "kwin";
        };
        # theme = "";
        enableHidpi = true;
      };
    };
  };

  xdg = {
    portal = {
      enable = true;
      wlr.enable = true;
      xdgOpenUsePortal = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];
      configPackages = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];
    };
  };
}
