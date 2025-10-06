#!/usr/bin/env sh

day_suffix() {
  d=$(date +%-d)
  case $d in
  1 | 21 | 31) s="st" ;;
  2 | 22) s="nd" ;;
  3 | 23) s="rd" ;;
  *) s="th" ;;
  esac
  echo "$(date +%b) ${d}${s}, $(date +%Y)"
}

sketchybar --set $NAME label="$(day_suffix)"
