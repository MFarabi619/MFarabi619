#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar nullglob

cd "$(git rev-parse --show-toplevel)"

trunk build --release
cd dist

DESTINATION=/SD:/www
HOSTNAME=xiao-sense.local
HOST=$(ping $HOSTNAME -c1 | head -1 | awk -F'[()]' 'NR==1{print $2}')
[ -z "$HOST" ] && {
  echo "couldn't resolve $HOSTNAME" >&2
  exit 1
}

mcumgrctl --udp "$HOST" shell "fs mkdir $DESTINATION" >/dev/null 2>&1 || true

for path in **/*; do
  if [[ -d $path ]]; then
    mcumgrctl --udp "$HOST" shell "fs mkdir $DESTINATION/$path" >/dev/null 2>&1 || true
  elif [[ -f $path ]]; then
    echo "→ $path"
    mcumgrctl --udp "$HOST" fs upload "$path" "$DESTINATION/$path"
  fi
done
