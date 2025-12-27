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
        wget
        exfat # exFAT support
        ntfs3g # ntfs support
        ffmpeg # terminal video/audio editing
        udiskie # manage removable media
        pciutils
        usbutils
        lm_sensors # system sensors
        tree-sitter
        brightnessctl # screen brightness control

        # cloudflared

        # i2c-tools # raspberry pi
      ]
      ++ lib.optionals config.networking.networkmanager.enable [
        networkmanager
        networkmanagerapplet
      ]
      ++ lib.optionals config.programs.hyprland.enable [
        kitty
      ]
      ++ lib.optionals config.programs.dconf.enable [
        dconf # configuration storage system
        dconf-editor
      ]
      ++ lib.optionals config.services.libinput.enable [
        libinput
        libinput-gestures # actions touchpad gestures using libinput
      ];

    pathsToLink = [
      "/share/mime"
      "/share/icons"
      "/share/fonts"
      "/share/themes"
      "/share/applications"
      "/share/bash-completion"
    ]
    ++ lib.optionals config.programs.zsh.enable [
      "/share/zsh"
    ]
    ++ lib.optionals config.programs.fish.enable [
      "/share/fish"
    ]
    ++ lib.optionals config.programs.xwayland.enable [
      "/share/wayland-sessions"
      "/share/xdg-desktop-portal"
    ];
  };
}
