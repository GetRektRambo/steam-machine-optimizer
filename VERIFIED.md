# Verification Receipts

## v6.3 Kernel Params — 2026-09-24

    cat /proc/cmdline | grep -o nowatchdog
    → nowatchdog

Status: VERIFIED — flags reached the running kernel after reboot.
Method: patched /esp/SteamOS/conf/*.conf (SteamOS Neptune systemd-boot layout).
Lesson: /etc/default/grub is a no-op on SteamOS — systemd-boot conf files are the real target.
