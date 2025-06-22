#!/bin/sh

set -e
THEME="theme.txt"

while :; do
  bsddialog --load-theme "$THEME" \
    --backtitle "DoomBSD Catacombs" \
    --title "Main Menu" \
    --yes-label "PROCEED" \
    --no-label "FLEE" \
    --menu \
    "Welcome traveller, you have come not seeking peace... but madness, mayhem, and the cursed power of the Void.

Be warned: this path leads only to insane efficiency, terminal sorcery, exceptional UNIX grokking, and ultimate aesthetic overfunction.

Begin the Rite of Configuration, ONLY IF YOU DARE!" \
    0 0 8 \
    "C" "Configuration Chamber" \
    "X" "󰏗 Extras" \
    "D" " The Summoning Ritual" \
    "L" "Study the Lore" \
    "?" "Cry for Help" \
    "P" "Profiles" \
    "U" "Update" \
    2>/tmp/menuitem.$$

  code=$?
  menuitem=$(cat /tmp/menuitem.$$)
  rm /tmp/menuitem.$$

  case $code in
  0) ;; # PROCEED
  1)
    bsddialog --load-theme "$THEME" --msgbox "Cowardice detected. Fleeing the void..." 6 50
    exit 1
    ;;
  3)
    bsddialog --load-theme "$THEME" --msgbox "You take a moment to collect yourself... but the ritual remains unfinished." 6 50
    continue
    ;;
  *)
    bsddialog --load-theme "$THEME" --msgbox "Unknown signal. The abyss stirs..." 6 50
    continue
    ;;
  esac

  case "$menuitem" in
  C)
    while :; do
      bsddialog --load-theme "$THEME" \
        --title "🛠 Configuration Chamber" \
        --yes-label "PROCEED" --no-label "RETREAT" \
        --form "Tune the machinery of your system:" 15 60 5 \
        "Hostname:" 1 1 "" 1 15 30 0 \
        "Timezone:" 2 1 "" 2 15 30 0 \
        "Username:" 3 1 "" 3 15 30 0 \
        "Shell:" 4 1 "/bin/zsh" 4 15 30 0 \
        2>/tmp/form.$$

      config_code=$?
      rm -f /tmp/form.$$

      case $config_code in
      0)
        bsddialog --load-theme "$THEME" --msgbox "System configuration accepted. The gears turn." 6 50
        break
        ;;
      1)
        bsddialog --load-theme "$THEME" --msgbox "Fled from the chamber. Nothing was touched." 6 50
        break
        ;;
      3)
        bsddialog --load-theme "$THEME" --msgbox "You retreat. The ritual awaits later..." 6 50
        break
        ;;
      *)
        bsddialog --load-theme "$THEME" --msgbox "The chamber echoes with confusion." 6 50
        break
        ;;
      esac
    done
    ;;

  X)
    break
    ;;

  D)
    bsddialog --load-theme "$THEME" --title " THE SUMMONING RITUAL" \
      --yesno "Begin the install/uninstall procedure for all selected rituals?" 0 60
    if [ $? -eq 0 ]; then
      {
        for i in $(seq 0 10 100); do
          echo XXX
          echo "$i"
          echo "Summoning progress: $i%"
          echo XXX
          sleep 0.1
        done
      } | bsddialog --load-theme "$THEME" --title "Invoking Rituals" --gauge "Casting spells..." 10 50 0
    fi
    ;;

  L)
    bsddialog --load-theme "$THEME" --title "📖 THE LORE" \
      --msgbox "DoomBSD draws inspiration from:\n\n- Doom Emacs by Henrik Lissner\n- HyDE Project (github.com/HyDE-Project)\n- ZaneyOS (by Tyler Kelley)\n- LazyVim (lazyvim.org)\n\nA testament to those who dare dream deeper in dotfiles and the dark." 14 70
    ;;

  ?)
    bsddialog --load-theme "$THEME" --title "❓ Cry for Help" \
      --msgbox "Need help?\n\n- Handbook: https://docs.freebsd.org/en/books/handbook/\n- DoomBSD Docs: No gods. No tech support. Only source code.\n- Community: Nonexistent :/" 12 60
    ;;

  P)
    bsddialog --load-theme "$THEME" \
      --title "📦 Profiles" \
      --menu "Choose a profile:" 0 0 3 \
      "default" "Minimal DoomBSD" \
      "dev" "Full developer stack" \
      "cyberdeck" "Graphical, Hyprland, bleeding edge"
    ;;

  U)
    bsddialog --load-theme "$THEME" \
      --title "󰚰 UPDATE" \
      --yesno "Run 'pkg update && pkg upgrade' now?" 0 50
    ;;

  *)
    bsddialog --load-theme "$THEME" --msgbox "The Void does not recognize this path..." 6 50
    ;;
  esac
done
