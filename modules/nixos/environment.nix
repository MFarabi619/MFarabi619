{
  lib,
  pkgs,
  config,
  ...
}:
{
  environment = {
    variables.NIXOS_OZONE_WL = "1";
    sessionVariables.NIXOS_OZONE_WL = "1";

    systemPackages =
      with pkgs;
      [
        tree-sitter

        # ========== Stylix ===========
        dconf # configuration storage system
        dconf-editor
        # =============================
        wget
        exfat # exFAT support
        ntfs3g # ntfs support
        udiskie # manage removable media
        brightnessctl # screen brightness control

        networkmanager
        networkmanagerapplet

        pciutils
        usbutils
        ffmpeg # terminal video/audio editing
        libinput # libinput library
        lm_sensors # system sensors
        libinput-gestures # actions touchpad gestures using libinput

        # cloudflared

        # i2c-tools # raspberry pi
      ]
      ++ lib.optionals config.programs.hyprland.enable [
        kitty
      ];

    pathsToLink = [
      "/share/mime"
      "/share/icons"
      "/share/fonts"
      "/share/themes"
      "/share/applications"
      "/share/bash-completion"
      "/share/wayland-sessions"
      "/share/xdg-desktop-portal"
    ]
    ++ lib.optionals config.programs.zsh.enable [
      "/share/zsh"
    ]
    ++ lib.optionals config.programs.fish.enable [
      "/share/fish"
    ];
  };
}
