#!/usr/bin/env bash
set -euo pipefail

ROOT="target/dx/web/release/web/public"
BASE_URL="http://ceratina.local/api/filesystem/sd"

c_reset=$'\033[0m'
c_dim=$'\033[2m'
c_bold=$'\033[1m'
c_cyan=$'\033[36m'
c_green=$'\033[32m'
c_yellow=$'\033[33m'
c_red=$'\033[31m'
c_magenta=$'\033[35m'

printf "\n  ${c_bold}${c_cyan}ceratina deploy${c_reset}\n"
printf "  ${c_dim}──────────────────────────────────────${c_reset}\n"

# printf "  ${c_dim}Flashing firmware ...${c_reset}\n"
# pio run -t upload || {
#   echo "${c_red}error:${c_reset} firmware flash failed" >&2
#   exit 1
# }
# printf "  ${c_green}flashed${c_reset}\n"

[ -d "$ROOT" ] || {
  echo "${c_red}error:${c_reset} missing dir $ROOT" >&2
  exit 1
}

# ── Prune stale assets ────────────────────────────────
# index.html references only the current build's hashed files.
# Previous builds leave orphaned assets that waste upload bandwidth.
if [ -f "$ROOT/index.html" ]; then
  stale=0
  for f in "$ROOT"/assets/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    # Skip .gz companions — they'll be removed with their source
    [[ "$base" == *.gz ]] && continue
    # Keep files referenced by index.html
    if grep -qF "$base" "$ROOT/index.html"; then
      continue
    fi
    # Keep files referenced by the main JS bundle
    main_js=$(grep -o 'assets/web-[^"]*\.js' "$ROOT/index.html" | head -1)
    if [ -n "$main_js" ] && [ -f "$ROOT/$main_js" ] && grep -qF "$base" "$ROOT/$main_js"; then
      continue
    fi
    rm -f "$f" "${f}.gz"
    ((stale += 1))
  done
  if ((stale > 0)); then
    printf "  ${c_yellow}pruned${c_reset} %d stale assets\n" "$stale"
  fi
fi

HOST="ceratina.local"
printf "  ${c_dim}Waiting for ${HOST} ...${c_reset}"
until ping -c1 -W1 "$HOST" &>/dev/null; do
  printf "${c_dim}.${c_reset}"
  sleep 1
done
printf " ${c_green}online${c_reset}\n"

human_size() {
  local bytes=$1
  if ((bytes >= 1048576)); then
    printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
  elif ((bytes >= 1024)); then
    printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
  else
    printf "%d B" "$bytes"
  fi
}

echo

printf "${c_dim}  Compressing ...${c_reset}"
compressed=0
find "$ROOT" -type f \( -name "*.wasm" -o -name "*.js" -o -name "*.css" -o -name "*.html" -o -name "*.svg" \) | while read f; do
  gzip -kf "$f"
done
printf " ${c_green}done${c_reset}\n"

mapfile -d '' files < <(find "$ROOT" -type f -print0 | sort -z)
total=${#files[@]}

upload_count=0
skip_count=0
total_bytes=0
for f in "${files[@]}"; do
  if [[ "$f" != *.gz ]] && [[ -f "${f}.gz" ]]; then
    ((skip_count += 1))
  else
    ((upload_count += 1))
    total_bytes=$((total_bytes + $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)))
  fi
done

printf "  ${c_dim}target${c_reset}  %s\n" "$BASE_URL"
printf "  ${c_dim}upload${c_reset}  ${c_bold}%d${c_reset} files  ${c_dim}(%s)${c_reset}\n" "$upload_count" "$(human_size $total_bytes)"
printf "  ${c_dim}skip${c_reset}    %d files  ${c_dim}(uncompressed originals)${c_reset}\n" "$skip_count"
printf "${c_dim}  ──────────────────────────────────────${c_reset}\n"
echo

start_ts=$(date +%s)
uploaded=0
uploaded_bytes=0

for f in "${files[@]}"; do
  rel="${f#"$ROOT"/}"

  if [[ "$f" != *.gz ]] && [[ -f "${f}.gz" ]]; then
    continue
  fi

  ((uploaded += 1))
  fsize=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
  uploaded_bytes=$((uploaded_bytes + fsize))

  ext="${rel##*.}"
  case "$ext" in
  gz) icon="$c_magenta" ;;
  wasm) icon="$c_yellow" ;;
  js) icon="$c_yellow" ;;
  css) icon="$c_cyan" ;;
  html) icon="$c_green" ;;
  svg | png) icon="$c_magenta" ;;
  bin) icon="$c_red" ;;
  *) icon="$c_dim" ;;
  esac

  printf "  ${c_dim}[%d/%d]${c_reset} ${icon}%s${c_reset} ${c_dim}(%s)${c_reset}\n" \
    "$uploaded" "$upload_count" "$rel" "$(human_size $fsize)"

  if ! curl -X PUT --fail --progress-bar \
    -o /dev/null \
    -F "file=@${f}" \
    "${BASE_URL}/${rel}"; then
    printf "  ${c_red}FAIL${c_reset} %s\n\n" "$rel"
    continue
  fi

  printf "  ${c_green}  ok${c_reset}\n"
done

elapsed=$(($(date +%s) - start_ts))
echo
printf "${c_dim}  ──────────────────────────────────────${c_reset}\n"
printf "  ${c_bold}${c_green}done${c_reset}  %d files  ${c_dim}%s in %ss${c_reset}\n" "$uploaded" "$(human_size $uploaded_bytes)" "$elapsed"
echo
