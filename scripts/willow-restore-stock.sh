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

for f in boot.img dtbo.img vbmeta.img; do
  [ -s "$dir/$f" ] || { echo "!! missing $dir/$f" >&2; exit 1; }
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
