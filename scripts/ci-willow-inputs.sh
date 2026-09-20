#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
ws=${1:?usage: ci-willow-inputs.sh <workspace-dir>}
mkdir -p "$ws/community-boot"
pin() { python3 -c "import sys,tomllib;print(tomllib.load(open('$repo/manifest.toml','rb'))['device']['willow'][sys.argv[1]])" "$1"; }
check() { echo "$2  $1" | sha256sum -c --quiet -; }

mkdir -p "$repo/sources/willow"
curl -fsSL --retry 5 -o "$repo/sources/willow/firmware.tar" https://github.com/bezilaszlo/moarchy/releases/download/willow-inputs/firmware.tar
check "$repo/sources/willow/firmware.tar" "$(pin firmware-sha256)"
mkdir -p "$ws/stock-rom/fw-willow"
tar -xf "$repo/sources/willow/firmware.tar" -C "$ws/stock-rom/fw-willow" --strip-components=5 --wildcards './qcom/sm6125/xiaomi/ginkgo/a610_zap.*'
tar -xf "$repo/sources/willow/firmware.tar" -C "$ws/stock-rom/fw-willow" --strip-components=2 ./qcom/a630_sqe.fw

curl -fsSL --retry 5 -o "$ws/community-boot/boot.img" https://github.com/Huabin1010/ginkgo-mainline-linux/releases/download/v0.4.0/boot.img
check "$ws/community-boot/boot.img" "$(pin boot-sha256)"
python3 - "$ws/community-boot" <<'PY'
import gzip, struct, sys, zlib
d = sys.argv[1]
b = open(d + '/boot.img', 'rb').read()
ksz, _, rsz, _, ssz = struct.unpack_from('<5I', b, 8)
page = struct.unpack_from('<I', b, 36)[0]
dsz = struct.unpack_from('<I', b, 1632 + 16)[0]
up = lambda n: -(-n // page) * page
kernel = b[page:page + ksz]
dtb_off = page + up(ksz) + up(rsz) + up(ssz)
open(d + '/kernel', 'wb').write(kernel)
open(d + '/dtb', 'wb').write(b[dtb_off:dtb_off + dsz])
image = gzip.decompress(kernel)
start = image.index(b'IKCFG_ST') + 8
open(d + '/config', 'wb').write(zlib.decompressobj(31).decompress(image[start:]))
PY

