{
  pkgs,
  ...
}:
{
  environment = {
    systemPackages =
      with pkgs;
      [
        coreutils
        alt-tab-macos
        kanata-with-cmd
      ]
      ++ lib.optionals (stdenv.x86_64) [
        yabai
        skhd
      ]
      ++ lib.optionals (stdenv.isAarch64) [
        macmon
      ];

    systemPath = [
      "/usr/local/bin"
      "/opt/homebrew/bin"
      "/Users/mfarabi/.local/bin"
      "/Users/mfarabi/.cargo/bin"
      # "/Users/mfarabi/.bun/bin"
      "/Users/mfarabi/Library/pnpm"
      # "/Users/mfarabi/.lmstudio/bin"
    ];

    pathsToLink = [
      "/share/zsh"
      "/Applications"
      "/share/bash-completion"
    ];
  };
}

# Read:

# github.com/jtroo/kanata/releases/tag/v1.9.0
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/main
# github.com/jtroo/kanata/discussions/1537

# Download:
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/main/dist/Karabiner-DriverKit-VirtualHIDDevice-6.2.0.pkg

# Install:
# /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate

# sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon' &
# sudo kanata -q &

# or

# sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon' &; sudo kanata -q &

# stop with:
# sudo killall Karabiner-VirtualHIDDevice-Daemon; sudo killall kanata

# Uninstall:
# bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/deactivate_driver.sh'
# sudo bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/remove_files.sh'
# sudo killall Karabiner-VirtualHIDDevice-Daemon
