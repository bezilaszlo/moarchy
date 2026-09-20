#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
ws=${1:?usage: ci-willow-inputs.sh <workspace-dir>}
mkdir -p "$ws/community-boot" "$ws/stock-rom/images" "$ws/stock-rom/fw-willow" "$ws/ginkgo-mainline-linux/firmware/ginkgo/wifi"
pin() { python3 -c "import sys,tomllib;print(tomllib.load(open('$repo/manifest.toml','rb'))['device']['willow'][sys.argv[1]])" "$1"; }
check() { echo "$2  $1" | sha256sum -c --quiet -; }

rom=willow_eea_global_images_V12.5.5.0.RCXEUXM_20220529.0000.00_11.0_eea_72d415294d.tgz
rom_sha=f408ebba1fa35e48f422b6f654404ae6c34e948805d72d8c1ad477f94fdfd6a8
curl -fsSL --retry 5 "https://cdnorg.d.miui.com/V12.5.5.0.RCXEUXM/$rom" | tee >(sha256sum | cut -d' ' -f1 > "$ws/rom.sha") |
  tar -xz -C "$ws/stock-rom" --strip-components=1 --wildcards '*/images/NON-HLOS.bin' '*/images/vendor.img'
[ "$(cat "$ws/rom.sha")" = "$rom_sha" ] || { echo "stock ROM sha256 mismatch" >&2; exit 1; }
check "$ws/stock-rom/images/NON-HLOS.bin" "$(pin non-hlos-sha256)"

python3 - "$ws/stock-rom/images/vendor.img" "$ws/stock-rom/images/vendor.raw" <<'PY'
import struct, sys
src = open(sys.argv[1], 'rb')
magic, _, _, fh, ch, blk, tb, tc, _ = struct.unpack('<IHHHHIIII', src.read(28))
assert magic == 0xed26ff3a
out = open(sys.argv[2], 'wb')
src.seek(fh)
for _ in range(tc):
    t, _, n, _ = struct.unpack('<HHII', src.read(ch))
    if t == 0xCAC1: out.write(src.read(n * blk))
    elif t == 0xCAC2: out.write(src.read(4) * (n * blk // 4))
    elif t == 0xCAC3: out.seek(n * blk, 1)
    elif t == 0xCAC4: src.read(4)
out.truncate(tb * blk)
PY
rm "$ws/stock-rom/images/vendor.img"
for f in a610_zap.mdt a610_zap.b00 a610_zap.b01 a610_zap.b02 a630_sqe.fw; do
  debugfs -R "dump /firmware/$f $ws/stock-rom/fw-willow/$f" "$ws/stock-rom/images/vendor.raw" 2>/dev/null
done
rm "$ws/stock-rom/images/vendor.raw"

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

curl -fsSL --retry 5 -o "$ws/ginkgo-mainline-linux/firmware/ginkgo/wifi/firmware-5.bin" \
  "https://raw.githubusercontent.com/Huabin1010/ginkgo-mainline-linux/$(pin wlan-descriptor-ref)/firmware/ginkgo/wifi/firmware-5.bin"
rm -f "$ws/rom.sha"
