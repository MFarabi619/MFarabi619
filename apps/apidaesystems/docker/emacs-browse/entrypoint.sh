#!/bin/sh
set -eu

# /home/browse is a fresh tmpfs at container start; lay out the
# Doom-expected paths as symlinks into the read-only image content.
mkdir -p "$HOME/.config" "$HOME/.cache"
ln -sf /opt/doom-emacs "$HOME/.config/emacs"
ln -sf /opt/doom-config "$HOME/.config/doom"

exec ttyd \
    -W \
    -t fontSize=16 \
    -t "fontFamily='JetBrainsMono Nerd Font'" \
    -t enableSixel=true \
    -t "titleFixed=Apidae Systems --- read-only Emacs" \
    -t disableLeaveAlert=true \
    -m 20 \
    -p 7681 \
    -- emacs -nw /repo/README.org
