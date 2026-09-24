# Changelog

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
