{
  lib,
  pkgs,
  config,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      ispell
      tree-sitter
      # cloudflared
    ];

    pathsToLink = [
      "/share/bash-completion"
    ]
    ++ lib.optionals (config.programs.zsh.enable || pkgs.stdenv.isDarwin) [ "/share/zsh" ]
    ++ lib.optionals config.programs.fish.enable [ "/share/fish" ];
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    variables.NIXOS_OZONE_WL = "1";
    sessionVariables.NIXOS_OZONE_WL = "1";

    systemPackages =
      with pkgs;
      [
        nixpacks
        buildpack

        wget
        exfat # exFAT support
        ntfs3g # ntfs support

        ffmpeg # terminal video/audio editing
        udiskie # manage removable media
        pciutils
        usbutils
        lm_sensors # system sensors
        brightnessctl # screen brightness control
        # i2c-tools # raspberry pi
      ]
      ++ lib.optionals config.networking.networkmanager.enable [
        networkmanager
        networkmanagerapplet
      ]
      ++ lib.optionals config.programs.hyprland.enable [ kitty ]
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
    ]
    ++ lib.optionals config.programs.xwayland.enable [
      "/share/wayland-sessions"
      "/share/xdg-desktop-portal"
    ];
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    enableAllTerminfo = true;

    systemPackages =
      with pkgs;
      [
        alt-tab-macos
        coreutils-full
        kanata-with-cmd
      ]
      ++ lib.optionals stdenv.isAarch64 [
        macmon
      ];

    pathsToLink = [
      "/Applications"
    ];

    systemPath = [
      "/usr/local/bin"
      "/opt/homebrew/bin"
      "/Users/mfarabi/go/bin"
      "/Users/mfarabi/.bun/bin"
      "/Users/mfarabi/.local/bin"
      "/Users/mfarabi/.cargo/bin"
      "/Users/mfarabi/Library/pnpm"
      # "/Users/mfarabi/.lmstudio/bin"
    ];
  };
}

# For Darwin, read:

# github.com/jtroo/kanata/releases/tag/v1.9.0
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/main
# github.com/jtroo/kanata/discussions/1537

# Download:
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/main/dist/Karabiner-DriverKit-VirtualHIDDevice-6.2.0.pkg
# if macos < 13.0
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/v6.6.0/dist/Karabiner-DriverKit-VirtualHIDDevice-3.0.0.pkg

# Install:
# /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate

# sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon' &
#
# Or if macos < 13.0
# sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-DriverKit-VirtualHIDDeviceClient.app/Contents/MacOS/Karabiner-DriverKit-VirtualHIDDeviceClient'

# sudo kanata -q &

# or

# sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon' &; sudo kanata -q &

# stop with:
# sudo killall Karabiner-VirtualHIDDevice-Daemon; sudo killall kanata

# Uninstall:
# bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/deactivate_driver.sh'
# sudo bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/remove_files.sh'
# sudo killall Karabiner-VirtualHIDDevice-Daemon
