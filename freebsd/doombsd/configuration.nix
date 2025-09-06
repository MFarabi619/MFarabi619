# Obtain image; *memstick.img for USB flash, and/or *disk1.iso for virtual machine
# https://download.freebsd.org/snapshots/amd64/amd64/ISO-IMAGES/15.0/?C=M&O=D
# nix build; sudo cp result/install.sh ./install.sh                                                 ─╯
# scp mfarabi@10.0.0.145:~/workspace/MFarabi619/hosts/doombsd/install.sh .; ./install.sh

{ pkgs, lib }:

let
  packages = [
    { name = "git"; desc = "Git."; }
    { name = "lazygit"; desc = "Lazygit."; }
    { name = "zsh"; desc = "Shell."; }
    { name = "yazi"; desc = "Terminal file browser."; }
    { name = "fastfetch"; desc = "System info tool."; }
    { name = "figlet"; desc = "ASCII art banners."; }
    { name = "lolcat"; desc = "Rainbow output."; }
    { name = "wifimgr"; desc = "Wi-Fi manager."; }
    { name = "cava"; desc = "Audio visualizer."; }
    { name = "kitty"; desc = "GPU-accelerated terminal."; }
    { name = "dolphin"; desc = "File manager."; }
    { name = "swaylock-effects"; desc = "Wayland lockscreen."; }
    { name = "hyprland"; desc = "Wayland compositor."; }
    { name = "waybar"; desc = "Status bar."; }
    { name = "rofi"; desc = "Launcher."; }
    { name = "pavucontrol"; desc = "Volume control."; }
    { name = "neovim"; desc = "Text editor."; }
    { name = "jetbrains-mono"; desc = "Font."; }
  ];

  installCalls = builtins.concatStringsSep "\n\n" (map (pkg: ''
    if pkg info -e ${pkg.name}; then
      echo "==> ${pkg.name} already installed - ${pkg.desc}"
    else
      echo "-> Installing ${pkg.name} - ${pkg.desc}"
      # pkg install -y ${pkg.name}
    fi
  '') packages);

  script = ''
    #!/bin/sh

    # DoomBSD Installer Script

    vidcontrol -f /usr/share/vt/fonts/terminus-b32.fnt 2>/dev/null || true

    bsddialog --title "DoomBSD Installer" --msgbox "Welcome to the Summoning Ritual" 8 40

    echo "======================================"
    echo "Welcome to the DoomBSD Summoning Ritual"
    echo "======================================"
    echo "==== Installing DoomBSD Essentials ===="

    ${installCalls}

    echo "==== DoomBSD Core Tools Installed! ===="

    # figlet -f slant "DoomBSD" | lolcat
  '';

in
pkgs.writeTextFile {
  name = "install";
  destination = "/install.sh";
  text = script;
  executable = true;
}
