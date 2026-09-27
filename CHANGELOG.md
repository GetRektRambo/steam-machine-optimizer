# Changelog

## v6.3 — 2026-09-27
- Weekly SSD TRIM: enables the stock `fstrim.timer` when present
  (SteamOS ships it), custom fallback otherwise. First manual run
  trimmed 120GB across partitions. Verify is now 17 checks.
- Loggers hardened: a failed log-file write can no longer abort an
  optimization run (it previously masqueraded as a backup failure).
- `${USER:-root}` fallback in LOG_FILE for the systemd boot path.
- Known strata: duplicate `do_uninstall()` definitions from the v6.2
  lineage still present — harmless (bash uses the last definition),
  slated for a v6.4 cleanup.

## v6.3 (2026-09-24) — Public Release
- Added `--uninstall` function with backup-aware config restoration
- All previous fixes retained

## v6.2 (2026-09-24) — Gaming Mode Hardening
- Fixed duplicate CPU governor verification bug
- Switched gaming hooks to `graphical.target`
- Added CPU monitor timer (60s polling)

## v6.1 (2026-09-24) — Gaming Mode Hooks + THP Watcher
- Fixed swap fstab path and size verification
- Added THP runtime watcher
- Added GRUB autodetection

## v6.0 (2026-09-24) — Defensive Rewrite
- Trap-based read-only restore
- `die()` error propagation
- Signal-safe interrupts

## v5.0 (2026-09-23) — Merged Installer
- Combined optimizer + patcher + installer
- Idempotency marker

## v4.1 (2026-09-23) — Initial Optimization Suite
- CPU governor, memory sysctls, swap, THP, MGLRU, watchdog, I/O scheduler
