# Brief: worker-1 — finish the willow image pipeline (no phone needed)

Report to: the orchestrator session ("What is running windows on system"). Never ask the user; send
questions to the orchestrator as numbered proposals ("proceeding unless you object; B needs yes/no").
Do not spawn subagents.

## Checkout
`~/Work/moarchy-willow/moarchy-willow-port/` — git worktree of SimonSchubert/moarchy, branch
`willow-port`, base `edb4bd8`. It holds UNCOMMITTED work by a Codex agent (three willow packages,
header-v2 boot image support, a boot candidate, `docs/willow.md`). You own this worktree now.
Read first: `../PLAN.md` (whole file, esp. Constraints, Phase 0 results, 0.4–0.6, 1.5, 3.x) and
`docs/willow.md` (resume notes). Do not touch `../diag/`, `../community-boot/`, `../stock-rom/`
(read-only inputs, owned by the orchestrator) or the sibling `../moarchy/` checkout.

## Why
Bootloader unlock opens 2026-09-27. By then a flashable, verified moarchy image for the Redmi Note
8T (willow) must exist so unlock day is only: diagnostic gate → vbmeta/dtbo → `fastboot boot`.

## What
1. Review the inherited diff critically before building on it; fix what is wrong, keep what is right.
   Known open item from its notes: the staging script's fresh Docker extraction path is unverified.
2. Make `image/build.sh` accept `DEVICE=willow` end to end: dispatch, `image/boot/android-bootimg.sh`
   device facts, kernel metadata for a PREBUILT kernel (no modules.builtin — use the pinned config),
   willow verifier profile (non-A/B: no qbootctl, no q6voiced, no sargo firmware/services).
3. Build the aarch64 moarchy rootfs for willow in Docker and produce `boot.img` + `rootfs.img` +
   a flash script. Kernel + DTB + firmware are PINNED (v0.4.0 kernel/DTB, willow's own a610_zap/sqe,
   modem from willow's NON-HLOS.bin) — never repin silently.
4. Bake in what the prebuilt kernel forces: `DisableSandbox` in pacman.conf (no Landlock), a swapfile
   unit instead of zram, no audio expectations, sshd enabled with key-only login, USB network gadget
   on boot (same 172.16.42.1 scheme as `../diag/root/init`) so the device is reachable with no Wi-Fi.
5. Keep a debug boot variant: same kernel, small initramfs with USB shell, for black-screen cases.

## Non-goals
Kernel rebuilding, modem/calls, camera, audio, upstreaming, any change for sargo behaviour, pushing.
No flashing — there is no unlocked phone. No public GitHub issues.

## Proof required
- moarchy's existing tests still pass; willow tests pass; verifier passes for DEVICE=willow.
- Boot image re-parsed: header v2, offsets match `../community-boot/boot.img`, kernel+DTB sha256
  match the pins in `manifest.toml`.
- Rootfs boots to a login in QEMU (`-M virt`, the pinned Image works there; see PLAN 0.5b) or, if
  that is not feasible, state exactly why and what was checked instead.
- sargo build path unchanged (diff shows no behaviour change for DEVICE=sargo).

## Quality bar
Changes land in the existing files named above; new files only under `pkgbuilds/*willow*`,
`image/boot/*willow*`, `scripts/*willow*`, `docs/willow.md`. Match the repo's comment style but do
not write essays: one short line only where the code cannot show a constraint. No while-I'm-here
cleanup. Report LOC added per file.

## Commits
Conventional Commits, no agent attribution trailers, as few as review needs (typically: packages,
boot-image v2 support, build/verifier dispatch, docs). Verify git author is the user's PERSONAL
identity (`bezilaszlo`), not a work email, before committing. No push, no amend.

## Report format
Commit hashes, artifact paths + sha256, test/verifier output summary, LOC per file, deviations from
this brief, open risks for unlock day.
