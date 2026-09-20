#!/usr/bin/env bash
# Fill the gaps in packages/ from upstream's signed [moarchy] repo.
#
#   scripts/ci-willow-packages.sh [packages-dir]
#
# Every package this tree builds is already there and wins; a name that is only
# upstream's is downloaded, signature-checked against pkgbuilds/moarchy-keyring
# and vouched for in .build-manifest, so the image build consumes one set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGS="${1:-$REPO_ROOT/packages}"
CACHE="${PKGCACHE:-$REPO_ROOT/.cache/upstream}"
. "$REPO_ROOT/scripts/manifest.sh"

server=$(manifest_get repo server) || exit 1
keyid=$(manifest_get repo keyid) || exit 1
name=$(manifest_get repo name) || exit 1

mkdir -p "$PKGS" "$CACHE"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"; mkdir -m700 "$GNUPGHOME"
gpg --batch --quiet --import "$REPO_ROOT/pkgbuilds/moarchy-keyring/moarchy.gpg"

verify() {
  gpg --batch --status-fd=1 --verify "$1.sig" "$1" 2>/dev/null |
    grep -q "^\[GNUPG:\] VALIDSIG $keyid" ||
    { echo "!! $1 is not signed by $keyid" >&2; return 1; }
}

fetch() {
  local f="$1"
  [ -s "$CACHE/$f" ] || curl -fsSL --retry 5 -o "$CACHE/$f" "$server/$f"
  [ -s "$CACHE/$f.sig" ] || curl -fsSL --retry 5 -o "$CACHE/$f.sig" "$server/$f.sig"
}

rm -f "$CACHE/$name.db" "$CACHE/$name.db.sig"
fetch "$name.db"
verify "$CACHE/$name.db"

# What this tree built, read from the manifest and not from the directory: a
# cached packages/ already holds the copies this script put there last run.
[ -f "$PKGS/.build-manifest" ] || { echo "!! no $PKGS/.build-manifest" >&2; exit 1; }
have=$(awk 'NF == 2 && $2 ~ /\.pkg\.tar\./ { print $2 }' "$PKGS/.build-manifest" |
  sed -e 's/\.pkg\.tar\..*$//' -e 's/-[^-]*-[^-]*-[^-]*$//')

# A packages/ restored from a cache also holds last run's copies; anything this
# build does not vouch for goes, or two versions of a name reach the image.
for p in "$PKGS"/*.pkg.tar.*; do
  [ -e "$p" ] || continue
  grep -q "  ${p##*/}$" "$PKGS/.build-manifest" || rm -f "$p"
done

mkdir -p "$work/db" && tar xzf "$CACHE/$name.db" -C "$work/db"
took=0
for d in "$work"/db/*/; do
  pkg=$(awk '/^%NAME%$/{getline;print;exit}' "$d/desc")
  file=$(awk '/^%FILENAME%$/{getline;print;exit}' "$d/desc")
  if printf '%s\n' "$have" | grep -qx "$pkg"; then continue; fi
  fetch "$file"
  verify "$CACHE/$file"
  cp "$CACHE/$file" "$PKGS/$file"
  printf '%s  %s\n' "$(sha256sum "$PKGS/$file" | cut -d' ' -f1)" "$file" >> "$PKGS/.build-manifest"
  took=$(( took + 1 ))
done
echo "==> $took packages from $server, $(printf '%s\n' "$have" | grep -c . || true) from this tree"
