# moarchy on Redmi Note 8T (willow) — plan

Written 2026-09-20. Bootloader unlock opens 2026-09-27 ~16:00 CEST.
Goal: a reliable, customizable Linux handheld with moarchy's phone UI and Omarchy's visual style,
editable through configuration, QML, scripts, packages, and coding agents on-device or over SSH.
Expected result: Wi-Fi-only handheld. No calls; internal audio is unsupported by the pinned
kernel; camera is out of scope. This is not yet a daily-driver phone.

Success comes in order: boot and recovery → accelerated UI + touch/keyboard + remote access →
charging/sleep/wake/memory acceptance → personal themes, layout, gestures, and apps. Preserve the
working phone UI while customizing it. Hyprland is the current moarchy target, not a reason to
discard a usable handheld if another compositor later proves necessary.

## Constraints (user, 2026-09-20)

- The phone is never opened: no test points, no UART/serial pads.
- All work goes through this desktop, the USB cable, and the phone's own screen.
- Debug channels are therefore: fbcon on the display, USB networking + shell from the diagnostic
  ramdisk, `ramoops`/pstore after a crash, adb/fastboot. A kernel that dies before display and
  USB come up may leave only pstore, if crash capture works — start from the kernel demonstrated
  on ginkgo (still unproven on this willow), change one thing
  at a time, and always test with `fastboot boot` before flashing anything.
- Kernel strategy: prebuilt community kernel first; rebuild only for a concrete need.

## Facts this plan rests on

- Phone: willow_eea, MIUI 12.5.5, 4 GB RAM, non-A/B, touch = Novatek (Tianma NT36672A panel), `anti: 1`.
- moarchy needs three packages per device (kernel, firmware, device) plus pins in `manifest.toml`;
  rootfs and image builder are shared. Its boot backend assumes A/B + AVB (Pixel 3a). willow is non-A/B.
- Upstream Linux has willow's DTS but no GPU, panel, touch, Wi-Fi.
- Community project `Huabin1010/ginkgo-mainline-linux` claims all four working on Linux 7.0.
  **Its repo does not contain the source for that**: `linux/` is gitignored, the only patches
  in-tree are for the *other* panel, battery gauge and backlight, and its config enables
  `TOUCHSCREEN_NT36XXX_SPI`, a driver that does not exist in mainline. The working kernel exists
  only as prebuilt `boot.img` release binaries.

- The community project's flash guide says ginkgo only, "do not flash on willow". Its author has
  not tested an 8T. Both phones do report userdata as `mmcblk0p87` (seen over adb on this unit).

## Biggest risk

The immediate risk is hardware reliability on willow: display/GPU, input, charging, suspend and
USB recovery are not validated until unlock. Kernel source availability is a maintenance risk,
not a prerequisite for trying the pinned binary. Packaging and phone UX integration still need
their own checks; a desktop or diagnostic boot alone does not prove a usable handheld.

## Phase 0 — before unlock (no phone needed)

0.1 Stock ROM: download official `willow_eea V12.5.5.0.RCXEUXM` fastboot ROM. Verify md5
    against Xiaomi's published value. Keep as the restore path. Extract firmware:
    a6xx GPU zap, adsp/cdsp/modem (NON-HLOS.bin), wlanmdsp, venus, bdwlan, BT, touch fw.
0.2 Dissect the community release `boot.img` v0.4.0 (verify SHA256SUMS): unpack kernel + DTB +
    initramfs, decompile DTB to DTS, read embedded kernel config if present. Output: the exact
    DTS that works, the config, and a list of drivers not in mainline.
0.3 Source recovery is off the critical path. Keep the prebuilt kernel unless a measured blocker
    (for example charging, resume, or a required kernel feature) demands a rebuild. If needed:
    a) prepare a source request for the author; posting it is a separate external action;
    b) look for the out-of-tree pieces elsewhere (nt36xxx SPI touch driver, sm6125 GPU/Wi-Fi
       nodes — barni2000/linux, sm6125-mainline, LKML patches);
    c) reconstruct: mainline v7.0 + decompiled DTS + ported touch driver + changes to existing
       drivers. Known one: `a6xx_calc_ubwc_config()` for Adreno 610 (their GPU notes, 2026-08-19);
       without it frames are unreadable. Such edits cannot be recovered from DTS/config, so audit
       every doc in `docs/` for "change is in ..." statements and list them.
    Decision gate: if (c) is needed, that is real kernel work — days, not hours.
0.4 Build packages in the task-owned `moarchy-willow-port/` worktree (branch `willow-port`),
    modelled on sargo; leave the existing `moarchy/` checkout on its current branch:
    `linux-moarchy-sm6125`, `firmware-moarchy-willow`, `moarchy-device-willow`
    (1080x2340 at scale 3, no qbootctl, no q6voiced). WLAN requires the MPSS firmware/service
    despite telephony being out of scope. Package local firmware from the verified willow ROM;
    keep blob staging ignored by Git. Record artifact hashes and actual build results.
0.5 moarchy image pipeline — all needed before 0.6 can pass:
    - `image/boot/android-image.py` writes header v0 with appended DTB only; add header v2 with a
      separate DTB, preserving the measured v0.4.0 load addresses and page size;
    - `image/build.sh` dispatches `sargo` only; add `willow`;
    - the verifier requires qbootctl and sargo firmware/services; add a willow profile
      (non-A/B, no qbootctl, no q6voiced).
    - `image/boot/android-bootimg.sh` itself: `_set_device_facts` rejects anything but sargo,
      reads `usr/share/kernel/moarchy-sdm670/kernel.release`, and requires `modules.builtin` to
      check what is built in. A prebuilt kernel ships none of that. The willow kernel package
      must provide `kernel.release` from the binary's version string and the extracted config.
      Check the required built-in symbols directly; do not invent `modules.builtin` from Kconfig
      names. Any needed loadable module must come from the exact binary's build.
    Flash side: `vbmeta --disable-verification`, empty dtbo.
0.5b Diagnostic boot image for the first test: community kernel + DTB repacked with OUR ramdisk
    that mounts nothing writable — prints kernel log, partition table (`/proc/partitions`,
    by-partlabel), brings up USB networking, drops to a shell.
    The ramdisk MUST carry the audited firmware at the exact paths the retained DTB/kernel ask
    for, or a healthy phone fails the gate: `qcom/sm6125/xiaomi/ginkgo/a610_zap.{mdt,b0*}` and
    `qcom/a630_sqe.fw` from `stock-rom/fw-willow/`. Only the zap shader is TZ-signed (hence
    willow's own); SQE is unsigned microcode — willow's is version 0x190, which meets the v7.0
    driver's minimum, so the "firmware too old" rejection seen on ginkgo does not apply. Touch
    firmware is built into the kernel.
    **This kernel + DTB + firmware set is the pinned payload for every later boot image.** Wi-Fi/modem firmware is not part of this gate. Their stock ramdisk mounts userdata
    read-write and copies an overlay into it (`initramfs/init.c:193`), so it is not write-free.
0.6 Build the moarchy aarch64 rootfs in Docker and run the shared checks plus willow checks.
    Configure DisableSandbox for this Landlock-less kernel, retain package signature checks,
    and pin the kernel package. Enable SSH with a user-provided public key before first boot;
    a diagnostic telnet shell is for the isolated USB ramdisk, not the installed OS.
    Artifact stages are separate: packages built ≠ boot image verified ≠ rootfs verified ≠
    hardware booted. Never label an earlier stage as a ready-to-flash system.

## Phase 1 — unlock day (2026-09-27)

1.1 User runs `miunlock`; phone wipes. Re-enable USB debugging.
1.2 Save bootloader variables locally (redact identifiers before sharing). Back up personal data
    before unlock. After the diagnostic shell works, read back GPT and device-specific calibration
    partitions to the desktop before installation; the factory ROM does not replace unique NV.
1.3 `fastboot boot` the DIAGNOSTIC image from 0.5b (never the stock community boot.img).
    Pass = kernel log on screen AND a shell over USB showing: eMMC detected, partition labels match
    ginkgo's, userdata is p87, firmware loads (GPU, touch). A visible log alone is not a pass.
    Fail → stop, reboot to MIUI untouched, fall back (see below).

## Phase 1.5 — install prerequisites (common to BOTH routes, do once, right after the gate passes)

1.5.1 From this workspace: `fastboot --disable-verification --disable-verity flash vbmeta stock-rom/images/vbmeta.img`
1.5.2 `fastboot flash dtbo community-boot/dtbo-empty.img` (v0.4.0, sha256 verified). Stock dtbo kept in
      `stock-rom/images/` for restore.
1.5.3 Record `fastboot getvar all` before and after.
Nothing else is flashed here. boot stays stock until a system has passed its own `fastboot boot`.

## Hardware acceptance list (run on the FIRST real system, Ubuntu or moarchy — never skipped)

display + backlight control, touch, Wi-Fi association + throughput, GPU (GLES >= 3.0, renderer is
freedreno not llvmpipe), battery gauge + charging, suspend/resume, thermals under load (5 min GPU +
CPU), storage read/write on userdata, clean reboot and power-off, USB gadget reconnect.
Driver probing in the diagnostic shell does NOT substitute for this list.

## Phase 2 — Ubuntu hardware proof: DROPPED from the main route (user, 2026-09-20)

Ubuntu is only the community project's demo userspace; we want its kernel, not its OS. The main
route is Phase 1 → 1.5 → 3. Everything below is kept solely as a debugging fallback: use it only if
moarchy gives a black screen and the diagnostic shell + pstore cannot say whether the phone or
moarchy is at fault. The hardware acceptance list runs on moarchy (3.2b).

2.0 Rootfs artifact: only release v0.1.0 ships `rootfs.ext4.zst`; v0.2–v0.4 ship boot images only.
    **Kernel + DTB are pinned to v0.4.0 (`community-boot/`, sha256 verified) for every phase.**
    The Phase 1 gate validates exactly that pair; never swap in v0.1.0's boot.img afterwards.
    So: build the Ubuntu rootfs with their scripts in Phase 0, or use v0.1.0's rootfs ONLY with
    the v0.4.0 kernel. If a different kernel/DTB is ever needed, rerun the Phase 1 gate for it.
    Phase 2 is optional. Skipping it skips nothing else: prerequisites live in Phase 1.5 and the
    hardware acceptance list then runs in Phase 3 (step 3.2b).
2.1 Never flash the community boot.img as shipped: its ramdisk carries GINKGO GPU firmware and
    copies it into userdata (`scripts/build-initramfs.sh:89`), replacing what Phase 1 validated —
    a later GPU failure would then be ambiguous (firmware vs hardware). Repack instead: pinned
    kernel + DTB, their init + overlay, with every firmware file swapped for the pinned willow
    payload (both `/lib/firmware` and `/overlay/lib/firmware`). `fastboot boot` it first.
    Then flash Ubuntu rootfs to userdata + the repacked boot.
    Run the hardware acceptance list over USB SSH. Record results — this is the hardware ceiling.
2.2 Decision gate: no GPU acceleration → Hyprland is out → stop or switch to sway/pmOS.

## Phase 3 — moarchy

3.1 After Phase 1.5, flash the verified moarchy sparse rootfs to userdata, then `fastboot boot`
    its matching boot.img. Keep the diagnostic image available to inspect storage/logs; a
    production image without an initramfs is acceptable only if root mounting and firmware
    availability work. Otherwise retain an appropriate minimal initramfs.
3.2 Bring up in order: login + SSH → Hyprland → shell → touch/keyboard → Wi-Fi → pacman.
3.2b If Phase 2 was skipped: run the full hardware acceptance list here, before 3.3.
3.3 Make it persistent — `fastboot boot` never replaces the boot partition, so until this step
    every reboot returns to whatever is flashed there (after Phase 2: the community image, whose
    init would copy its Ubuntu overlay into moarchy's rootfs and mask tty1). Once 3.1–3.2 pass:
    `fastboot flash boot <moarchy boot.img>`, reboot WITHOUT a cable-side boot, confirm it comes
    up on its own twice. Until then, never let the phone reboot unattended with moarchy on
    userdata and the community image on boot. If Phase 2 was skipped, stock boot is still there
    and Android cannot boot the Linux userdata: return to fastboot manually rather than relying
    on Android recovery behavior or accepting any format/reset prompt.
3.4 Install Claude Code + Codex, sshd, keys. Measure RAM headroom; add a swapfile (no zram).

## Phase 4 — customize a working handheld

4.1 Save a known-good configuration and the installed package list. Keep the tested boot image
    and a desktop recovery path. Trial one theme/layout/gesture change at a time over SSH.
4.2 Start with moarchy's existing touch gestures, keyboard and adaptive apps; customize palette,
    fonts, spacing, launcher and shortcuts through its user configuration and QML surfaces.
    Keep local customizations under version control and identify which files packages own so an
    update cannot silently erase work. Choose specific visual changes after seeing the real UI.
4.3 Verify the result on the phone: keyboard usable in terminals, touch targets reachable,
    scrolling and transitions smooth, shell restart recovers cleanly, and sleep/wake still works.
4.4 Local builds or a personal pacman repository for the three device packages; keep the kernel
    pinned. Publishing/signing infrastructure can follow a usable device; no GitHub push is implied.

## Fallbacks

- Kernel unobtainable/unbuildable → REPACK, do not reuse their boot.img: extract kernel + DTB,
  pair with our own ramdisk (or none) and cmdline. Their image carries Ubuntu-specific startup:
  the overlay masks GDM and `getty@tty1`, which would break moarchy's autologin. Modules must
  match the prebuilt kernel (mostly built-in; check). No custom config possible — pacman needs
  Landlock; check in 0.2, and if absent pacman on-device needs `--disable-sandbox`.
- 8T does not boot the ginkgo kernel → restore stock with the fastboot ROM; LineageOS + Termux,
  or a Pixel 3a for moarchy.
- Restore at any point: `scripts/willow-restore-stock.sh` (boot, dtbo, vbmeta, erase userdata;
  hash-checked against V12.5.5.0.RCXEUXM). The stock `flash_all.sh` is a gated last resort only:
  it writes xbl/abl/tz and raises anti-rollback. Never `flash_all_lock.sh`.

## Not doing

Calls/SMS/modem, camera, upstreaming to moarchy (maintainer excludes devices needing kernel work).

## Review log

2026-09-20 — reviewed by Codex (gpt-6-astra) in the adjacent Herdr pane; five findings, all verified
against source and folded in: first boot not write-free (0.5b, 1.3), prebuilt fallback needs
repacking, GPU driver change missing from reconstruction (0.3c), no pinned rootfs (2.0), image
pipeline changes wider than the boot backend (0.5).
Second pass, four findings, all verified and folded in: moarchy was never flashed persistently
(3.3), backend script itself needs willow + prebuilt-kernel metadata (0.5), kernel/DTB pinned to
v0.4.0 across phases (2.0), diagnostic ramdisk must carry GPU firmware (0.5b).
Third pass, two findings + one correction, folded in: prerequisites and hardware acceptance made
common to both routes (1.5, acceptance list, 3.2b); firmware pinned with kernel/DTB and the Ubuntu
boot image repacked with it (2.1); SQE is not TZ-signed, only zap is (0.5b).

## Phase 0 results (2026-09-20)

0.1 Stock ROM — done. `stock-rom/` holds the verified tgz plus extracted `images/` (boot, dtbo,
    vbmeta, vendor.raw, NON-HLOS.bin, BTFM.bin, dspso.bin, partition.xml) and `fw-willow/`.
0.2 Community boot.img v0.4.0 — done, in `community-boot/` (sha256 verified):
    - Linux 7.0.0 "-dirty", header v2, separate DTB, gzip kernel, cmdline roots on
      `/dev/disk/by-partlabel/userdata`, `init=/init`.
    - Kernel config IS embedded → `community-boot/config` (9516 lines).
      Present: MODULES, INITRD, DEVTMPFS_MOUNT, FHANDLE, CGROUPS, SECCOMP_FILTER, USB ECM/NCM/RNDIS,
      PSTORE_RAM, DRM_MSM, ATH10K_SNOC, BT_HCIUART_QCA, EXT4.
      Missing: **SECURITY_LANDLOCK** (pacman on-device needs `DisableSandbox` in pacman.conf),
      **ZRAM** (use a swapfile instead on 4 GB), **SND_SOC_QCOM** (no audio at all), F2FS.
    - Working DTS recovered → `community-boot/ginkgo-working.dts` (2619 lines): gpu@5900000
      (adreno-610.0) + gmu wrapper, panel `tianma,ginkgo-fhd-video`, touchscreen
      `novatek,NVT-ts-spi`, wifi@c800000 (wcn3990), modem remoteproc (sm6115-mpss-pas),
      ktd3136 backlight, pmi632-qg battery gauge.
    - Out-of-tree pieces a rebuild would need: nt36xxx SPI touch driver, `tianma,ginkgo-fhd-video`
      panel compatible, pmi632-qg gauge, ktd3136 backlight, a6xx ubwc change, sm6125 gpu/wifi/mpss
      SoC nodes.
    willow vs ginkgo, measured:
    - Partition table: 87 entries, **identical order**; userdata = p87, boot = p72 on both.
    - Touch firmware (tianma + ebbg): **byte-identical**.
    - GPU zap shader + sqe: **different builds** (same ELF header, different signed segment).
      TrustZone verifies the zap signature (not SQE, which is unsigned), so ship willow's own files from `fw-willow/`, placed at
      the path the DTB asks for (`qcom/sm6125/xiaomi/ginkgo/a610_zap.mdt`). Same for modem.mdt:
      take it from willow's NON-HLOS.bin, not from the community repo.
0.5b Diagnostic boot image — done, sources in `image/diag-willow/` (`build.sh` rebuilds
    `images/diag-willow/boot-diag-willow.img` reproducibly and rewrites `SHA256SUMS`; unlock-day
    script `run-diag.sh`). Built from the original header (v2, same offsets) with only ramdisk
    size, cmdline and id patched; kernel and DTB verified byte-identical to v0.4.0.
    Ramdisk: static aarch64 BusyBox 1.38 (docker `busybox:musl`), willow's a610_zap + a630_sqe,
    `init` that mounts only proc/sys/devtmpfs/devpts/tmpfs/configfs/debugfs/pstore, waits for the
    partition table to settle (87), sets every mmcblk node read-only (re-applied every 15 s),
    forces USB device role, RNDIS gadget 172.16.42.1 + DHCP for the host, telnetd :23, httpd :80
    (`/report.txt`, `/dmesg.txt`), and repaints a status report on the screen every 15 s. The
    report shows the NVT touch-firmware result (OK/FAIL/NOT SEEN), rw block-node count (want 0)
    and an unbound CDC-ECM probe. `panic=30` so a kernel panic reboots to MIUI by itself.
    Claim: the image mounts and writes no partition data. It is NOT "touches nothing": the kernel's
    eMMC init sets EXT_CSD device registers exactly as Android does on every boot. The DTB's
    /chosen bootargs contain `root=... rw init=/init`; this is inert because an initramfs /init
    exists: v7.0 `kernel_init_freeable()` only calls `prepare_namespace()` (the only path that
    mounts root) when `init_eaccess(ramdisk_execute_command)` fails. Residual risk: an initramfs
    that failed to unpack would fall through to mounting userdata rw; the ramdisk is hash-pinned
    and QEMU-tested. The pinned DTB is not modified.
    Build: `WORK=<dir with community-boot/ and stock-rom/> image/diag-willow/build.sh` (inputs
    hash-checked against `inputs.sha256`, busybox fetched from docker). Run: `run-diag.sh` after
    unlock; it prints (never runs) the sudo/nmcli commands if the host does not pick up DHCP.
    Hard hang: hold Power ~10 s (hardware reset) — returns to MIUI, nothing was flashed.
    Tested in QEMU (`-M virt`, same Image + ramdisk): init runs, report renders, telnetd starts.
    NOT testable before unlock: panel, GPU firmware load, USB gadget, eMMC detection.
    Seen in the kernel log: the touch driver reads the panel vendor from the cmdline and defaults
    to tianma — correct for this unit (Novatek touch), wrong for a Huaxing panel.

## Current checkpoint (2026-09-20, stopped at user request)

- Plan revised: reliable handheld first, ricing after hardware acceptance; kernel reconstruction
  is conditional. Ubuntu remains a debugging fallback. No phone commands were run this session.
- Implementation lives in `moarchy-willow-port/`, branch `willow-port`, based on `edb4bd8`.
  Changes are uncommitted. The original `moarchy/` checkout remains clean on `main`.
- Three local packages built successfully with host makepkg (data-only recipes, no ARM compilation):
  `linux-moarchy-sm6125-7.0.0.v0.4.0-1-aarch64`, `firmware-moarchy-willow-12.5.5-1-any`, and
  `moarchy-device-willow-0.5.0-1-any`. Archives are in `moarchy-willow-port/packages/willow/`.
  Runtime dependencies were not installed/tested; the existing `moarchy-qcom-modem` package is
  still needed by the device package. Local package archives are unsigned.
- Firmware extracted from the verified NON-HLOS image; GPU/WLAN/MPSS inputs and the deterministic
  firmware archive are hash-pinned in the port's `manifest.toml`. Blobs stay Git-ignored under
  `sources/willow/`. Firmware installs under `/usr/lib/firmware/moarchy-willow`, selected through
  `firmware_class.path` in the boot cmdline to avoid distribution package file conflicts.
  The c3j Wi-Fi BDF is a candidate; calibration/service behavior still needs hardware validation.
- Android image writer now supports header v2 and separate DTB while retaining v0 behavior.
  `images/willow-boot-candidate/boot.img` was generated with the pinned kernel/DTB, no ramdisk,
  `root=PARTLABEL=userdata`, `init=/sbin/init`, pinned firmware lookup path, and `panic=0`.
  This is a boot candidate ONLY: no moarchy rootfs has been built or flashed.
- Validation: all three package builds and their checks passed; 3 willow boot tests passed,
  including byte-for-byte reconstruction of the real v0.4.0 image. Existing v0/AVB checks passed
  except the sargo image round-trip, explicitly skipped because its fixture is unavailable.
  Shell syntax and `git diff --check` passed. Existing staged inputs were reverified; the new
  staging script's fresh Docker extraction path has not yet been exercised end-to-end.

Resume with `moarchy-willow-port/docs/willow.md`. Next work, in order:

1. Finish image/backend and verifier dispatch for willow; connect the prebuilt config checks,
   firmware path, device package and header-v2 writer. Do not pretend the backend is integrated.
2. Integrate the installed OS's DisableSandbox/kernel pin, USB access and SSH key provisioning;
   validate MPSS/rmtfs/tqftpserv paths and avoid enabling unsupported zram.
3. Build and verify the full rootfs, then test the staging script from fresh inputs and inspect
   packaged firmware/ELF segments. Keep input payload hashes unchanged unless deliberately repinned.
4. Unlock-day diagnostic and hardware acceptance remain pending. No flashing, commits, pushes,
   or external source-request issue were performed.
