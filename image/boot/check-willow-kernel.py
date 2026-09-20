#!/usr/bin/env python3
"""Check real extracted config and kernel identity instead of inventing module metadata."""
import gzip
from pathlib import Path
import sys


def check(kernel, config, release):
    settings = dict(line.split('=', 1) for line in config.splitlines()
                    if line.startswith('CONFIG_') and '=' in line)
    required = ('ARM64', 'BLK_DEV_INITRD', 'DEVTMPFS', 'DEVTMPFS_MOUNT', 'EFI_PARTITION',
                'MMC', 'MMC_BLOCK', 'MMC_SDHCI_MSM', 'ARM_SMMU', 'EXT4_FS', 'FHANDLE',
                'CGROUPS', 'SECCOMP', 'SECCOMP_FILTER', 'NAMESPACES', 'TMPFS',
                'DRM_MSM', 'TOUCHSCREEN_NT36XXX_SPI', 'SWAP',
                # ECM is what the installed OS raises (devices.md D19); RNDIS is
                # what the diagnostic ramdisk raises. One kernel serves both.
                'USB_CONFIGFS_ECM', 'USB_CONFIGFS_RNDIS')
    missing = [f'CONFIG_{name}=y' for name in required
               if settings.get(f'CONFIG_{name}') != 'y']
    if missing:
        raise ValueError('not built in: ' + ', '.join(missing))
    if ('Linux version ' + release + ' ').encode() not in gzip.decompress(kernel):
        raise ValueError('kernel release does not match the pinned binary')


if __name__ == '__main__':
    try:
        check(Path(sys.argv[1]).read_bytes(), Path(sys.argv[2]).read_text(), sys.argv[3])
    except (ValueError, OSError) as error:
        sys.exit(str(error))
    print('willow kernel identity and required built-ins verified; hardware remains untested')
