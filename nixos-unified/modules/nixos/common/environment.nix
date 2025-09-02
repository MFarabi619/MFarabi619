{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      wget          # when curl doesn't work

      brightnessctl # screen brightness control
      udiskie # manage removable media
      ntfs3g # ntfs support
      exfat # exFAT support

      networkmanager
      networkmanagerapplet

      libinput-gestures # actions touchpad gestures using libinput
      libinput # libinput library
      lm_sensors # system sensors
      pciutils # pci utils
      usbutils # usb utils
      ffmpeg # terminal video/audio editing

      # ========== Stylix ===========
      dconf # configuration storage system
      dconf-editor # dconf editor

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
