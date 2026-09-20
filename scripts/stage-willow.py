#!/usr/bin/env python3
"""Stage pinned binary inputs from the existing workspace; never access a phone."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
PIN = tomllib.loads((REPO / 'manifest.toml').read_text())['device']['willow']


def verify(path, digest):
    with path.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != digest:
        raise ValueError(f'checksum mismatch: {path}')


def stage(source, target, digest):
    verify(source, digest)
    if target.exists():
        verify(target, digest)
    else:
        shutil.copyfile(source, target)


def main(workspace):
    workspace = workspace.resolve()
    output = REPO / 'sources/willow'
    output.mkdir(parents=True, exist_ok=True)
    for filename, name, pin in (
        ('boot.img', 'community-boot.img', 'boot-sha256'),
        ('kernel', 'Image.gz', 'kernel-sha256'),
        ('dtb', 'sm6125-xiaomi-ginkgo.dtb', 'dtb-sha256'),
        ('config', 'config', 'config-sha256'),
    ):
        stage(workspace / 'community-boot' / filename, output / name, PIN[pin])
    archive = output / 'firmware.tar'
    if archive.exists():
        verify(archive, PIN['firmware-sha256'])
        print('All willow source artifacts already staged and checksums verified')
        return
    rom = workspace / 'stock-rom/images'
    verify(rom / 'NON-HLOS.bin', PIN['non-hlos-sha256'])
    descriptor = workspace / 'ginkgo-mainline-linux/firmware/ginkgo/wifi/firmware-5.bin'
    verify(descriptor, PIN['wlan-descriptor-sha256'])
    with tempfile.TemporaryDirectory(prefix='stage-', dir=output) as temporary:
        temp = Path(temporary)
        extracted = temp / 'non-hlos'
        extracted.mkdir()
        subprocess.run([
            'docker', 'run', '--rm',
            '--mount', f'type=bind,src={rom},dst=/rom,readonly',
            '--mount', f'type=bind,src={extracted},dst=/out',
            'alpine:3.20', 'sh', '-c',
            'apk add --no-cache mtools >/dev/null && '
            'mcopy -i /rom/NON-HLOS.bin "::image/modem.*" "::image/modemr.jsn" '
            '"::image/modemuw.jsn" "::image/wlanmdsp.mbn" "::image/bdf_c3j.bin" /out/'
        ], check=True)
        firmware = temp / 'firmware'
        qcom = firmware / 'qcom/sm6125/xiaomi/ginkgo'
        wifi = firmware / 'ath10k/WCN3990/hw1.0'
        qcom.mkdir(parents=True)
        wifi.mkdir(parents=True)
        stock = workspace / 'stock-rom/fw-willow'
        for name in ('a610_zap.mdt', 'a610_zap.b00', 'a610_zap.b01', 'a610_zap.b02'):
            shutil.copyfile(stock / name, qcom / name)
        shutil.copyfile(stock / 'a630_sqe.fw', firmware / 'qcom/a630_sqe.fw')
        for source in sorted(extracted.glob('modem*')):
            shutil.copyfile(source, qcom / source.name)
        shutil.copyfile(extracted / 'wlanmdsp.mbn', wifi / 'wlanmdsp.mbn')
        shutil.copyfile(extracted / 'bdf_c3j.bin', wifi / 'board.bin')
        shutil.copyfile(descriptor, wifi / 'firmware-5.bin')
        candidate = temp / 'firmware.tar'
        subprocess.run(['tar', '--sort=name', '--mtime=@0', '--owner=0', '--group=0',
                        '--numeric-owner', '--mode=u+rwX,go+rX,go-w', '-cf', str(candidate),
                        '-C', str(firmware), '.'], check=True)
        verify(candidate, PIN['firmware-sha256'])
        shutil.copyfile(candidate, archive)
    print('Willow kernel, DTB, config and GPU/WLAN firmware staged and verified')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
