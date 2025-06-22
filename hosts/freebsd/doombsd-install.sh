#!/bin/sh

# USB internet tethering
# sudo dhclient ue0
# ssh-keygen -t ed25519 -C "mfarabi619@gmail.com"
# cat ~/.ssh/id_ed25519.pub
# git config --global user.name "Mumtahin Farabi"
# git config --global user.email "mfarabi619@gmail.com"
# BROWSER=false gh auth login -p=ssh -h="github.com"
# in /etc/rc.conf, by kbdmap and then selecting "United States of America (Caps Lock acts as Left Ctrl)
# keymap="us.ctrl.kbd"
vidcontrol -f /usr/share/vt/fonts/terminus-b32.fnt

# sudo pkg install yazi
# sudo pkg install octopkg

bsddialog --title "DoomBSD Installer" --msgbox "Welcome to the Summoning Ritual >:(" 8 40

# Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

install_pkg() {
  PKG="$1"
  DESC="$2"

  if pkg info -e "$PKG"; then
    echo -e "${YELLOW} $PKG already installed,${RESET} - $DESC"
  else
    echo -e "${CYAN} ->
    Installing $PKG...${RESET} - $DESC"
    # sudo pkg install -y "$PKG"
  fi
}

echo -e "${RED}======================================"
echo "Welcome to the DoomBSD Summoning Ritual"
echo "======================================"
echo -e "${GREEN}==== Installing DoomBSD Essentials ===${RESET}"

# choice=$(gum choose "Install ZSH + p10k theme" "Install Lazyvim" "Install Doom Emacs" "Install Hyprland" "Quit")
#
# case "$choice" in
#   "Install ZSH")
#     echo "Install ZSH"
#   ;;
#   "Quit")
#     echo "See you in the void."
#     exit 0
#     ;;
# esac

install_pkg git "Git."
install_pkg lazygit "Lazygit."
install_pkg zsh "Shell."
install_pkg yazi "Terminal file browser."
install_pkg fastfetch "Shows system info like neofetch, but faster."
install_pkg figlet "Fun ASCII art banners for termina."
install_pkg lolcat "Rainbow output - makes everything more metal."
install_pkg wifimgr "Simple GUI for managing Wi-Fi."
install_pkg cava "Terminal audio spectrum visualizer."
install_pkg kitty "GPU-accelerated terminal with ligatures & graphics support."
install_pkg dolphin "Powerful and sleek file manager."
install_pkg swaylock-effects "Fancy lock screen for Wayland with blure/shadow."
install_pkg hyprland "Dynamic tiling Wayland compositor."
install_pkg waybar "Status bar for Wayland compositors."
install_pkg rofi "Application launcher and dmenu replacement."
install_pkg pavucontrol "PulseAudio volume control."
install_pkg neovim "Your trusted DoomBSD config editor."
install_pkg jetbrains-mono "Typeface."

echo -e "${GREEN}==== DoomBSD Core Tools Installed ! ====${RESET}"

figlet -f slant "DoomBSD" | lolcat;

# gum style --border double --padding "1 2" --margin "1 0" --foreground 212 "Installation complete."

# sudo pkg install git dbus xdg-desktop-portal wayland xwayland qt6-wayland xdg-desktop-portal-hyprland hyprland-qt-support hyprland-qtutils nwg-dock-hyprland hyprgraphics hyprlang hyprutils hyprwayland-scanner hyprsunset hypridle hyprlock hyprpaper hyprpicker imlib2-jxl gimp-jxl-plugin mousepad wl-clipboard wlogout swaylock-effects nwg-look byobu kvantum nsxiv pamixer pa-applet wmwifi sddm sddm-freebsd-black-theme wayland wayland-logout wayland-protocols wayland-utils xwayland xwayland-run xwayland-satellite xwaylandvideobridge aimage qimageblitz qt6-imageformats xloadimage terminal-image-viewer bsd-splash-changer bsdebfetch bsdinfo bsdsensors pwcbsd wmbsdbatt openconnect-freebsd-daemon viewglob sysctlview webcamd pwcview fontpreview xdg-terminal-exec swww pango cairo pipewire
