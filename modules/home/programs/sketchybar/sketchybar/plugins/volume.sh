#!/usr/bin/env sh

# The volume_change event supplies $INFO = current volume percentage (0–100)

if [ "$SENDER" = "volume_change" ]; then
  VOLUME="$INFO"

  case "$VOLUME" in
  100 | 9[0-9]) ICON="󰕾" ;;       # high
  [6-8][0-9]) ICON="󰕾" ;;         # high (same icon as above)
  [3-5][0-9]) ICON="󰖀" ;;         # medium
  [1-9] | [1-2][0-9]) ICON="󰕿" ;; # low
  0 | *) ICON="󰖁" ;;              # muted
  esac

  sketchybar --set volume_logo icon="$ICON" --set volume label="${VOLUME}%"
fi
