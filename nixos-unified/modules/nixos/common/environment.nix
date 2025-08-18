{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
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

      # ========== Stylix ===========
      dconf # configuration storage system
      dconf-editor # dconf editor
      zsh-powerlevel10k
      meslo-lgs-nf

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
