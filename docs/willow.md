# Redmi Note 8T (willow): local experimental port

A Wi-Fi-only handheld on moarchy's phone UI. Hardware is untested until the
bootloader unlocks; nothing here has run on a phone. `../PLAN.md` from this
worktree holds the phases and the unlock-day constraints.

The kernel is a pinned community BINARY (`Huabin1010/ginkgo-mainline-linux`
v0.4.0), not a build of ours. It has no Landlock, no ZRAM and no Qualcomm
internal audio, and it ships no modules. Kernel, DTB, extracted config, kernel
release and the firmware archive are pinned by sha256 in `[device.willow]` in
`manifest.toml`. Never repin silently: `image/verify.sh` compares the image's
`/boot/Image.gz` and DTB against those hashes.

## Build

```sh
bash scripts/stage-willow.sh          # vendor blobs -> sources/willow (hash-checked)
./scripts/provision.sh build          # packages, in the aarch64 container
DEVICE=willow MOARCHY_SSH_KEY=~/.ssh/id_ed25519.pub ./scripts/build-image.sh
./scripts/verify-image.sh images/moarchy-willow-<version>-<date>
```

`MOARCHY_SSH_KEY` is required for willow and the build refuses without it: with
no wifi credentials and no proven display, ssh over the USB gadget is the only
way in. The image is therefore marked `/etc/moarchy-debug-image` — it carries
one person's key and must never be published.

Staging needs `../community-boot`, `../stock-rom` and `../ginkgo-mainline-linux`
in the workspace beside this worktree. Without `sources/willow`, the package
build skips the two recipes that need it and builds everything else.

On a host whose qemu binfmt registration lacks the `C` flag, `sudo` inside the
aarch64 container cannot elevate and every `makepkg -s` fails to install its
dependencies. Either register binfmt with `C`, or build from an image derived
from `moarchy-builder` with those dependencies already installed.

## Packages

`linux-moarchy-sm6125` packages the prebuilt kernel and the ginkgo DTB, with
`kernel.release` taken from the binary's banner and the config extracted from
that same binary. It fabricates no `modules.builtin`: `backend_kernel` checks
the required symbols in that config instead.

`firmware-moarchy-willow` packages willow's own signed zap shader and MPSS
segments, its SQE microcode, the WLAN image and the c3j board file, under
`/usr/lib/firmware/moarchy-willow`. The boot cmdline points
`firmware_class.path` there, so these win over `linux-firmware`'s copies of the
same names without either package owning the other's paths. The c3j board file
is the community's candidate, not a verified calibration choice for willow.

`moarchy-device-willow` supplies scale 3, filesystem-only growth, and three
package-enabled units: the MPSS starter that Wi-Fi needs (WCN3990's firmware
runs on the modem DSP), the USB network gadget, and the swapfile. No qbootctl
(non-A/B), no q6voiced (no audio).

## What the pinned kernel forces

- `DisableSandbox` in the image's `/etc/pacman.conf`, written by
  `backend_kernel`. Signature checking is untouched.
- A 2 GiB swapfile on userdata, created on first boot, instead of zram.
- CDC-ECM on `usb0` at 172.16.42.1/24, raised by `moarchy-willow-usbnet` and
  left alone by NetworkManager. From the desktop:
  `sudo ip addr add 172.16.42.2/24 dev <iface> && ssh moarchy@172.16.42.1`.
  Risk: RNDIS is the only gadget function anyone has seen working on this UDC
  (the community system uses it, and so does the diagnostic ramdisk). ECM is
  enabled in the pinned config but unproven on this hardware; devices.md D19
  is why the installed OS uses it anyway.

## Boot artifact

Header v2 with a separate DTB, because that is what the community image the
bootloader accepted looks like. `image/boot/test-willow-boot.py` rebuilds that
image byte-for-byte from its own parts, which is the evidence that the v2
writer is right.

The artifact is `boot.img`, `rootfs.simg` and `flash.sh` — no vbmeta of ours.
Partitions this project writes, and no others:

| when | partition |
|---|---|
| Phase 1.5, once, from the workspace | `vbmeta`, `dtbo` |
| `flash.sh` | `userdata` |
| `flash.sh --persist`, after a typed confirmation | `boot` |

`anti: 1` on this unit: nothing here flashes a partition from another ROM
version, and nothing touches `xbl`, `abl`, `tz`, `hyp`, `rpm`, `keymaster`,
`cmnlib` or `devcfg` at all.

`flash.sh` refuses any phone that does not report `product: willow`, flashes
the rootfs, then `fastboot boot`s the kernel from RAM, so a phone that shows
nothing is one power cycle from MIUI. The boot partition stays stock until
`--persist`, which is PLAN 3.3 and not before.

For a black screen, the diagnostic image (`image/diag-willow/`) is the way in:
same kernel and DTB, a ramdisk with USB networking and a shell.

## Not proven

No hardware has run any of this. A verified image is not a booting phone: the
panel, GPU firmware load, touch, Wi-Fi association, charging, suspend and USB
recovery are all unknown until the gate in PLAN 1.3 passes.
