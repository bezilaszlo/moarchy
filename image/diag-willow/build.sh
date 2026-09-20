#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
WORK=${WORK:-$repo/..}
out=$repo/images/diag-willow
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

BOOT=$WORK/community-boot/boot.img
FW=$WORK/stock-rom/fw-willow
sha() { sha256sum "$1" | cut -d' ' -f1; }
want() { grep " $1\$" "$here/inputs.sha256" | cut -d' ' -f1; }
check() { [ "$(sha "$1")" = "$(want "$2")" ] || { echo "input hash mismatch: $2" >&2; exit 1; }; }

check "$BOOT" community-boot/boot.img
for f in a610_zap.b00 a610_zap.b01 a610_zap.b02 a610_zap.mdt a630_sqe.fw; do check "$FW/$f" stock-rom/fw-willow/$f; done

mkdir -p "$stage/root/bin" "$stage/root/etc" "$stage/root"/{dev,proc,sys,tmp,run,sbin,var/lib/misc}
cid=$(docker create --platform linux/arm64 busybox:musl)
docker cp "$cid":/bin/busybox "$stage/root/bin/busybox"; docker rm "$cid" >/dev/null
check "$stage/root/bin/busybox" busybox
ln -s busybox "$stage/root/bin/sh"
install -m 755 "$here/init" "$stage/root/init"
install -m 644 "$here/udhcpd.conf" "$stage/root/etc/udhcpd.conf"
fwd=$stage/root/lib/firmware/qcom
mkdir -p "$fwd/sm6125/xiaomi/ginkgo"
install -m 644 "$FW"/a610_zap.{mdt,b00,b01,b02} "$fwd/sm6125/xiaomi/ginkgo/"
install -m 644 "$FW/a630_sqe.fw" "$fwd/a630_sqe.fw"

mkdir -p "$out"
find "$stage/root" -exec touch -h -d @0 {} +
(cd "$stage/root" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet --reproducible) | gzip -n -9 > "$stage/ramdisk.cpio.gz"

python3 - "$BOOT" "$stage/ramdisk.cpio.gz" "$out/boot-diag-willow.img" <<'PY'
import hashlib, struct, sys
src, rd_path, dst = sys.argv[1:]
d = open(src, 'rb').read()
PAGE = struct.unpack_from('<I', d, 36)[0]
(ksz, _, rsz, _, ssz, *_) = struct.unpack_from('<10I', d, 8)
hdr_ver = struct.unpack_from('<I', d, 40)[0]
assert d[:8] == b'ANDROID!' and hdr_ver == 2 and ssz == 0 and PAGE == 4096
rec_sz, rec_off, hdr_sz, dtb_sz = struct.unpack_from('<IQII', d, 1632)
assert rec_sz == 0
up = lambda n: -(-n // PAGE) * PAGE
kern = d[PAGE:PAGE + ksz]
dtb_off = PAGE + up(ksz) + up(rsz)
dtb = d[dtb_off:dtb_off + dtb_sz]
assert len(d) == dtb_off + up(dtb_sz)
rd = open(rd_path, 'rb').read()
cmdline = (b"console=ttyMSM0,115200n8 console=tty0 keep_bootcon ignore_loglevel loglevel=8 "
           b"clk_ignore_unused fw_devlink.sync_state=disabled androidboot.hardware=qcom "
           b"rdinit=/init panic=30")
h = bytearray(d[:PAGE])
struct.pack_into('<I', h, 16, len(rd))
h[64:64 + 512] = cmdline.ljust(512, b'\0')
sha = hashlib.sha1()
for blob in (kern, rd, b'', b'', dtb):
    sha.update(blob); sha.update(struct.pack('<I', len(blob)))
h[576:608] = sha.digest().ljust(32, b'\0')
pad = lambda b: b + b'\0' * (up(len(b)) - len(b))
img = bytes(h) + pad(kern) + pad(rd) + pad(dtb)
open(dst, 'wb').write(img)
o = bytes(d[:PAGE]); n = bytes(h)
diff = [i for i in range(PAGE) if o[i] != n[i]]
assert all(16 <= i < 20 or 64 <= i < 576 or 576 <= i < 608 for i in diff), diff
assert img[PAGE:PAGE + ksz] == kern and img[len(img) - up(dtb_sz):][:dtb_sz] == dtb
PY

(cd "$out" && sha256sum boot-diag-willow.img) | tee "$here/SHA256SUMS"
