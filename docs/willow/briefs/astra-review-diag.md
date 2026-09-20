Review only — do not implement or edit anything. Target: ~/Work/moarchy-willow/diag/ (root/init,
run-diag.sh, SHA256SUMS, boot-diag-willow.img) against PLAN.md steps 0.5b and 1.3.
Check: (1) is the "writes nothing to eMMC" claim true for the whole boot, including kernel-side
behaviour with this cmdline and DTB; (2) can a healthy phone fail the gate because of this image
(firmware paths, timing, USB role, RNDIS on the host); (3) can the image leave the phone in a state
that does not return to MIUI; (4) is the on-screen report sufficient to decide pass/fail without USB.
Output: findings with severity and file:line, nothing else. No files changed.
