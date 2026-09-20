# Brief: worker-2 — fork + fold project files into the worktree + diag hardening

Report to the orchestrator session ("What is running windows on system"). Never ask the user;
questions to the orchestrator as numbered proposals. No subagents.

## Shared checkout rules
`~/Work/moarchy-willow/moarchy-willow-port/` (branch `willow-port`) is OWNED BY worker-1, who is
mid-task with uncommitted changes. You may NOT edit, stage or commit anything there except the new
paths named in task B, and you commit only your own paths (`git commit --only <paths>`).
Coordinate with worker-1 (session name `moarchy-willow-ac`) by SendMessage before your first commit.

## A. Fork (user authorized, 2026-09-20: "ok, fork it")
1. `gh auth status` — the active GitHub account MUST be the personal one, `bezilaszlo`. If it is
   anything else (e.g. a work account), STOP and report; do not switch accounts yourself.
2. `gh repo fork SimonSchubert/moarchy --clone=false` under bezilaszlo. Public fork is fine.
3. In the worktree add it as remote `fork` (leave `origin` = upstream untouched).
4. Do NOT push yet. Pushing happens once, after worker-1's commits land and the orchestrator says so.
   Before any future push: git author + committer on every willow-port commit must be the personal
   identity, not a work email.

## B. Fold the unversioned project files into the worktree (new paths only)
- `../PLAN.md`            -> `docs/willow/PLAN.md`
- `../briefs/*.md`        -> `docs/willow/briefs/`
- `../diag/root/init`, `../diag/root/etc/udhcpd.conf`, `../diag/run-diag.sh`, `../diag/SHA256SUMS`
                          -> `image/diag-willow/` (sources only)
- Add `image/diag-willow/build.sh` that rebuilds `boot-diag-willow.img` reproducibly from the pinned
  inputs (`../community-boot/boot.img`, `../stock-rom/fw-willow/`, busybox from docker
  `busybox:musl` linux/arm64) — the logic is in PLAN.md "0.5b" and must reproduce: original header
  bytes with only ramdisk size, cmdline and id patched; kernel+DTB byte-identical to v0.4.0.
- No binaries in git (no busybox, no .img, no firmware). Add them to `.gitignore` if needed —
  `.gitignore` is already modified by worker-1's inherited diff, so ask worker-1 to add the lines.
Keep the originals in place until the orchestrator confirms; copy, do not move.

## C. Harden the diagnostic init (review findings, 2026-09-20)
1. Report must prove touch firmware actually loaded: grep dmesg for the NVT driver's firmware
   update result and show success/fail explicitly, not just the input device name.
2. Read-only invariant: wait until the partition count is stable (expect 87), set every mmcblk node
   read-only, and re-apply inside the 15 s loop; report `ro` for mmcblk0 AND count of rw partitions
   (want 0).
3. Host side: `run-diag.sh` must not depend on NetworkManager guessing right. After `fastboot boot`,
   wait for the RNDIS interface (MAC 02:00:00:00:42:01), print its state, and if it has no
   172.16.42.x address within 20 s print the exact `nmcli`/`ip` command for the user (do not run
   sudo). Also print an IPv6 link-local telnet fallback.
4. Wording: the claim is "mounts and writes no partition data". Kernel eMMC init sets EXT_CSD
   device registers exactly as Android does on every boot; say so in a comment and in PLAN 0.5b.
   The DTB's /chosen bootargs contain `root=… rw init=/init`; with an initramfs that has /init the
   kernel never mounts root, so it is inert — verify that reasoning against v7.0 `init/main.c` /
   `init/do_mounts*.c` and state the result in the report. Do NOT modify the pinned DTB.
5. Hang case: document in run-diag.sh output that a hard hang needs Power held ~10 s (hardware
   reset), which returns to MIUI because nothing was flashed.
6. Re-test in QEMU exactly as PLAN 0.5b describes; init must still reach the report.

## Non-goals
Anything in worker-1's scope (packages, image/build.sh, rootfs), pushing, flashing, GitHub issues.

## Commits (on willow-port, own paths only)
`docs(willow): add port plan and briefs`, `feat(willow): diagnostic boot image sources`.
Conventional Commits, no agent attribution trailers, body <= 5 lines. No amend.

## Report
Fork URL, `gh auth status` account, commit hashes, new img sha256, QEMU output tail, answers to C4,
LOC per file, deviations.
