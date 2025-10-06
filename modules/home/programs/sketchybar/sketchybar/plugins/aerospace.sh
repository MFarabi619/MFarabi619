#!/usr/bin/env bash
set -euo pipefail

# make sure it's executable with:
# chmod +x ~/.config/sketchybar/plugins/aerospace.sh

# Script is called by sketchybar for each item that subscribed, with:
#   NAME=space.<id>           (sketchybar sets this)
#   FOCUSED_WORKSPACE=<id>    (you pass this from Aerospace via --trigger)

ITEM="${NAME:-}"
FOCUSED="${FOCUSED_WORKSPACE:-}"

# If NAME isn't set (e.g. running by hand), bail quietly
[ -z "${ITEM}" ] && exit 0

# Extract this item's workspace id: "space.3" -> "3"
SID="${ITEM#space.}"

if [ "${SID}" = "${FOCUSED}" ] && [ -n "${FOCUSED}" ]; then
  # Make sure the item actually shows; highlight the focused one
  sketchybar --set "${ITEM}" drawing=on icon.highlight=on background.drawing=on
else
  # Still show the item, just not highlighted
  sketchybar --set "${ITEM}" drawing=on icon.highlight=off background.drawing=on
fi
