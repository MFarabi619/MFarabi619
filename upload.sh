#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar nullglob

HOST=10.0.0.172
DEST=/SD:/www

trunk build --release

mcumgrctl --udp "$HOST" shell "fs mkdir $DEST" >/dev/null 2>&1 || true

cd dist
for path in **/*; do
  if [[ -d $path ]]; then
    mcumgrctl --udp "$HOST" shell "fs mkdir $DEST/$path" >/dev/null 2>&1 || true
  elif [[ -f $path ]]; then
    echo "→ $path"
    mcumgrctl --udp "$HOST" fs upload "$path" "$DEST/$path"
  fi
done
