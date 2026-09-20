#!/usr/bin/env python3
"""Round-trip the actual v0.4.0 image and test important boot-format failures."""
import importlib.util
from pathlib import Path
import struct
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('android_image', REPO / 'image/boot/android-image.py')
ai = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ai)


class WillowBootTests(unittest.TestCase):
    def test_community_roundtrip(self):
        source = REPO / 'sources/willow/community-boot.img'
        if not source.exists():
            self.skipTest('run scripts/stage-willow.sh for the pinned fixture')
        original = source.read_bytes()
        ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack_from('<10I', original, 8)
        recovery, offset, header, ds, da = struct.unpack_from('<IQIIQ', original, 1632)
        self.assertEqual((ss, hv, recovery, offset, header), (0, 2, 0, 0, 1660))
        pad = lambda size: (size + ps - 1) // ps * ps
        ramdisk_start = ps + pad(ks)
        dtb_start = ramdisk_start + pad(rs)
        cmdline = (original[64:576].rstrip(b'\0') + original[608:1632].rstrip(b'\0')).decode()
        rebuilt = ai.make_bootimg(original[ps:ps + ks], original[ramdisk_start:ramdisk_start + rs],
                                 cmdline, page_size=ps, kernel_addr=ka, ramdisk_addr=ra,
                                 second_addr=sa, tags_addr=ta, os_version=osv,
                                 header_version=2, dtb=original[dtb_start:dtb_start + ds], dtb_addr=da)
        self.assertEqual(rebuilt, original)

    def test_no_ramdisk_separate_dtb(self):
        image = ai.make_bootimg(b'K' * 5000, b'', 'root=PARTLABEL=userdata',
                               header_version=2, dtb=b'DTB')
        self.assertEqual(struct.unpack_from('<I', image, 16)[0], 0)
        self.assertEqual(image[12288:12291], b'DTB')
        self.assertEqual(struct.unpack_from('<I', image, 1648)[0], 3)

    def test_invalid_inputs(self):
        for kwargs in ({'header_version': 2}, {'header_version': 1},
                       {'page_size': 1000}, {'dtb': b'dtb'}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                ai.make_bootimg(b'kernel', b'', '', **kwargs)


if __name__ == '__main__':
    unittest.main()
