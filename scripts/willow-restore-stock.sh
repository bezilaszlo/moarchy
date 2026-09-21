#!/bin/bash
set -euo pipefail

usage() { echo "usage: $0 [--dry-run] <stock images dir>" >&2; exit 1; }

dry=0
dir=
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    -*) usage ;;
    *) [ -z "$dir" ] || usage; dir=$a ;;
  esac
done
[ -n "$dir" ] || usage

export PATH="$HOME/.local/opt/platform-tools:$PATH"
command -v fastboot >/dev/null || { echo "!! fastboot not on PATH" >&2; exit 1; }

STOCK_ROM='willow_eea V12.5.5.0.RCXEUXM'
# A boot chain from another ROM version is the anti-rollback trap, so hashes decide, not filenames.
sum() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
for pair in \
  boot.img:0bc5c5f6ae68119d1182a39a033693115748af180a9945ea38a51800e0908748 \
  dtbo.img:e955e0c87ad32904d2d0bb891483c4a70bba8a530b385ead4039437ca20dc878 \
  vbmeta.img:bba7dbd799a6261c1e2a63bd31fd900f6cbe2837e21507badad7515ffbd7e074; do
  f=${pair%%:*}; want=${pair#*:}
  [ -s "$dir/$f" ] || { echo "!! missing $dir/$f" >&2; exit 1; }
  got=$(sum "$dir/$f")
  [ "$got" = "$want" ] || {
    echo "!! $dir/$f is not $STOCK_ROM ($got) -- refusing" >&2; exit 1; }
done

getvar() { fastboot getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }
product=$(getvar product)
[ "$product" = willow ] || { echo "!! product '${product:-unknown}', not willow -- refusing" >&2; exit 1; }
unlocked=$(getvar unlocked)
[ "$unlocked" = yes ] || { echo "!! unlocked: ${unlocked:-unknown} -- refusing" >&2; exit 1; }

run() {
  echo "+ $*"
  [ "$dry" = 1 ] || "$@"
}

if [ "$dry" = 0 ]; then
  echo "Restores stock boot, dtbo, vbmeta from $dir and ERASES userdata. The bootloader stays unlocked."
  read -r -p "Type RESTORE to continue: " reply
  [ "$reply" = RESTORE ] || { echo "not confirmed; nothing written" >&2; exit 1; }
fi

# anti: 1 -- only these three; never xbl/abl/tz/modem, never a lock command.
run fastboot flash vbmeta "$dir/vbmeta.img"
run fastboot flash dtbo "$dir/dtbo.img"
run fastboot flash boot "$dir/boot.img"
run fastboot erase userdata
run fastboot reboot
