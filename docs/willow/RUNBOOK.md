# willow unlock day

USB cable and the phone screen only. One step at a time; on any "stop if", stop.
Workspace `W=~/Work/moarchy-willow`, worktree `$W/moarchy-willow-port`. In every shell:

```sh
export PATH=$HOME/.local/opt/platform-tools:$PATH
W=~/Work/moarchy-willow
```

Never run `flash_all_lock.sh`. Never accept a format/reset prompt on the phone. Back up personal data first: step 2 wipes the phone.

## 0. Fresh artifacts (CI artifacts expire after 7 days)

```sh
cd $W/moarchy-willow-port
head=$(git rev-parse HEAD)
gh workflow run willow-image.yml --ref willow-port
sleep 15
run=$(gh run list --workflow willow-image.yml --branch willow-port --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$run"
gh run view "$run" --json headSha,conclusion,headBranch
rm -rf /tmp/willow && gh run download "$run" -n willow-image -D /tmp/willow/image && gh run download "$run" -n willow-diag-image -D /tmp/willow/diag
(cd /tmp/willow/image && sha256sum -c SHA256SUMS)
(cd /tmp/willow/diag && sha256sum -c $W/moarchy-willow-port/image/diag-willow/SHA256SUMS)
(cd $W/community-boot && sha256sum dtbo-empty.img) && grep dtbo-empty $W/community-boot/SHA256SUMS
```

Expect: `headSha` equals `$head`, `headBranch` is `willow-port`, `conclusion` is `success`; every
line `OK`; the two dtbo hashes match. Both downloads name that same run id.
Stop if: the run fails, the SHA or branch is not yours, any hash differs, or the diag image no longer
matches the committed `SHA256SUMS`.

## 1. Bootloader

```sh
adb reboot bootloader
fastboot getvar product
```

Expect: FASTBOOT screen; `product: willow`.
Stop if: anything other than `willow`.

## 2. Unlock (you run this, not an agent)

```sh
PATH=$HOME/.local/opt/platform-tools:$PATH ~/Work/moarchy-willow/miunlock/.venv/bin/miunlock
```

Expect: unlock succeeds, userdata is wiped, MIUI setup starts. Re-enable USB debugging, then:

```sh
adb reboot bootloader
fastboot getvar unlocked
fastboot getvar all 2>&1 | tee $W/getvar-before.txt
```

Expect: `unlocked: yes`. The getvar file holds identifiers: keep it local.
Stop if: miunlock reports a remaining wait time or an error, or `unlocked: no`.

## 3. Diagnostic gate (nothing is flashed)

```sh
DIAG_IMG=/tmp/willow/diag/boot-diag-willow.img $W/moarchy-willow-port/image/diag-willow/run-diag.sh
curl -s http://172.16.42.1/report.txt
curl -s http://172.16.42.1/dmesg.txt > $W/dmesg-willow.txt
telnet 172.16.42.1
```

Pass needs ALL of: kernel log and status report on the phone screen; a shell over USB;
eMMC detected with 87 partitions; partition labels match ginkgo's, `userdata` is p87 (`boot` p72);
GPU firmware loaded (a610 zap + a630 sqe); touch firmware `OK`; rw block-node count `0`;
the `ecm:` line read and recorded.
A visible log without a shell is not a pass. The `ecm:` line is information for step 7, not a stop:
whatever it says, it does not fail this gate.
From the shell, read back GPT and the calibration partitions to the desktop before installing.
Leave with `reboot -f` (returns to MIUI), then `adb reboot bootloader`.
Stop if: any criterion fails. Frozen or black screen: hold Power ~10 s; MIUI returns. Do not go on.

## 4. Phase 1.5 prerequisites (once)

```sh
cd $W
fastboot --disable-verification --disable-verity flash vbmeta stock-rom/images/vbmeta.img
fastboot flash dtbo community-boot/dtbo-empty.img
fastboot getvar all 2>&1 | tee $W/getvar-after.txt
```

Expect: `OKAY` / `Finished` for both; `product` and `anti` unchanged between the getvar files.
Stop if: any `FAILED`. Nothing else is flashed here; boot stays stock.

## 5. Install

```sh
cd /tmp/willow/image && bash ./flash.sh
```

Expect: `==> userdata` takes several minutes (sparse chunks), then `fastboot boot`.
First boot takes minutes: the rootfs grows into userdata. The swapfile appears on the second boot.
Then `sudo ip addr add 172.16.42.2/24 dev <iface> && ssh moarchy@172.16.42.1`.
Stop if: flash.sh refuses (locked / not willow) or any `FAILED`.
Black screen after 5 min: hold Power, Vol-down to fastboot, rerun step 3 to look.
Stock boot cannot start this userdata: after any reboot return to fastboot by hand and `fastboot boot boot.img`.

## 6. Hardware acceptance (never skipped)

Bring-up order: login + SSH, Hyprland, shell, touch/keyboard, Wi-Fi, pacman. Then record each:
display + backlight control; touch; Wi-Fi association + throughput; GPU (GLES >= 3.0, renderer
freedreno, not llvmpipe); battery gauge + charging; suspend/resume; thermals under 5 min GPU + CPU
load; storage read/write on userdata; clean reboot and power-off; USB gadget reconnect.

Stop if: no GPU acceleration, or charging/resume is broken. Record, do not persist.

## 7. `usb0` never appears

See "ECM fallback" in `../willow.md`: boot the diagnostic image, read its `ecm:` line. Do not add RNDIS to the image.

## 8. Persist (only after two good boots of this exact image and step 6 recorded)

```sh
cd /tmp/willow/image
fastboot devices                                    # exactly one line, or set ANDROID_SERIAL
serial=${ANDROID_SERIAL:-$(fastboot devices | awk 'NR==1 {print $1}')}
bash ./flash.sh --persist && fastboot -s "$serial" reboot
```

Expect: prompt, type `PERSIST`; then the phone comes up on its own, twice, with no cable-side boot.

Checkpoint after EACH reboot, before triggering the next one: `ssh moarchy@172.16.42.1` answers, and
a spot-check of step 6 (display, touch, Wi-Fi association, charging) passes. Write it down. An
unobserved reboot does not count as one of the two, and the second reboot does not start until the
first is recorded.

Stop if: `flash.sh --persist` exits non-zero — the `&&` means the reboot does not run and nothing
was written — or it does not come up, or a checkpoint fails. Go to step 9 or `fastboot boot` the
diagnostic image.

## 9. Restore

```sh
$W/moarchy-willow-port/scripts/willow-restore-stock.sh $W/stock-rom/images
```

Writes stock boot, dtbo, vbmeta and erases userdata; stays unlocked; MIUI runs first-time setup.
Full-ROM `flash_all.sh` is the last resort and needs the whole ROM re-extracted (`stock-rom/images/` holds a subset).
