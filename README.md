# Steam Machine Optimizer

A set-and-forget system optimizer for Steam Machines and SteamOS desktop PCs.

Runs once, sets up everything, then quietly defends those settings against
anything that tries to change them — including SteamOS itself. Comes with a
full uninstall that puts everything back the way it was.

---

## What This Actually Does (Compared to Stock)

This will not double your FPS. What it does is make the system *tighter* —
fewer stutters, smoother frame times, and no crashes when games eat RAM.

| Setting | Stock SteamOS | With This Script | Why It Matters |
|---|---|---|---|
| CPU governor | `schedutil` | `performance` | Better frame pacing, costs idle power |
| Swappiness | 60 | 20 | Less swapping under load |
| Swap | zram only | zram + 20GB disk | Graceful degradation vs crash |
| THP | varies | `madvise`, defrag never | Kills random 200ms freezes |
| MGLRU | often unused | enabled | Smarter memory reclaim |
| Kernel watchdog | active | disabled | Less latency jitter |

**Who this is for:** Wall-powered Steam Machines/desktops. Not for Steam Deck or laptops on battery.

---

## Setup (One Command, Then Play)

1. **Clone the repo** (Desktop Mode only):

```bash
git clone https://github.com/GetRektRambo/steam-machine-optimizer.git
cd steam-machine-optimizer
chmod +x SteamOpt-v6.2-x86_64.sh
./SteamOpt-v6.2-x86_64.sh --install

```

2. **Reboot** — kernel params need a restart.

3. **Verify**:

```bash
./SteamOpt-v6.2-x86_64.sh --verify
```

You want **16 passed, 0 failed**.

4. **Play.** Settings persist in the background.

---

## After a SteamOS Update

If settings disappear after a SteamOS update:

```bash
./SteamOpt-v6.2-x86_64.sh --reapply && ./SteamOpt-v6.2-x86_64.sh --verify
```

Keep the repo folder — it's your post-update tool.

---

## Commands

| Command | What it does |
|---|---|
| `--install` | One-time setup + install boot service |
| `--run` | Apply optimizations interactively |
| `--verify` | Check current state, changes nothing |
| `--reapply` | Re-apply after a SteamOS update |
| `--uninstall` | Remove everything, restore from backup |

---

## Uninstalling

```bash
./SteamOpt-v6.2-x86_64.sh --uninstall

```

Restores GRUB/fstab/sysctl from backup, removes services/hooks, optionally
deletes swap file, re-enables read-only filesystem. Backups kept in
`~/steam-optim-backup-*`.

---

## Troubleshooting

- Failed verification → `--reapply` then `--verify` again
- Governor not `performance` while gaming → wait 60s for the monitor
- Swap not created → check space: `df -h /home` (~25GB needed)
- Broken? → open a GitHub issue with `--verify` output and `/tmp/steam-machine-opt-*.log`

---

## License

MIT — © GetRektRambo 2026

Built through six versions on an actual Steam Machine. Buy yourself a coffee on my behalf.
