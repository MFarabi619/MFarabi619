{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      # ========== Stylix ===========
      dconf # configuration storage system
      dconf-editor # dconf editor
      # =============================

      wget
      ntfs3g # ntfs support
      exfat # exFAT support
      udiskie # manage removable media
      brightnessctl # screen brightness control

      networkmanager
      networkmanagerapplet

      pciutils
      usbutils
      lm_sensors # system sensors
      libinput # libinput library
      ffmpeg # terminal video/audio editing
      libinput-gestures # actions touchpad gestures using libinput

      # cloudflared

      # i2c-tools # raspberry pi
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
    };

    pathsToLink = [
      "/share/zsh"
      "/share/bash-completion"
      "/share/icons"
      "/share/themes"
      "/share/fonts"
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];
  };
}
