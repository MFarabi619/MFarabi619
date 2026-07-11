#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar nullglob

trunk build --release
cd dist

DEST=/SD:/www
mcumgrctl --udp "$HOST" shell "fs mkdir $DEST" >/dev/null 2>&1 || true
for path in **/*; do
  if [[ -d $path ]]; then
    mcumgrctl --udp "$HOST" shell "fs mkdir $DEST/$path" >/dev/null 2>&1 || true
  elif [[ -f $path ]]; then
    echo "→ $path"
    mcumgrctl --udp "$HOST" fs upload "$path" "$DEST/$path"
  fi
done
