{
  pkgs,
  ...
}:
{
  environment = {

    variables = {
      NIXOS_OZONE_WL = "1";
    };

    systemPackages = with pkgs; [
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
    ];

    pathsToLink = [
      "/share/zsh"
      "/share/icons"
      "/share/themes"
      "/share/fonts"
      "/share/applications"
      "/share/bash-completion"
      "/share/xdg-desktop-portal"
    ];
  };
}
