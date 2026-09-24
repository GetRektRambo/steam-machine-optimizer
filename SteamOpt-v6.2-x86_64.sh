#!/bin/bash
# ====================================================================
# STEAM MACHINE OPTIMIZER v6.2 — ROBUST GAMING MODE BUILD
# ====================================================================
# Author: GetRektRambo
# License: MIT (c) 2026
#
# CHANGELOG v6.2 (from v6.1):
#   - Fixed duplicate CPU governor verification bug
#   - Switched gaming hooks from gamescope-session.target → graphical.target
#   - Added CPU monitor timer (polles every 60s to enforce performance)
#   - Improved THP gaming hook delay (waits up to 50s for sysfs)
#   - All v6.0/v6.1 fixes retained
# ====================================================================

set -uo pipefail
IFS=$'\n\t'

# ── Runtime Configuration ───────────────────────────────────────────
declare -r SCRIPT_NAME="$(basename "$0")"
declare -r SCRIPT_PATH="$(readlink -f "$0")"
declare -r LOG_FILE="/tmp/steam-machine-opt-${SUDO_USER:-$USER}.log"
declare -r MARKER_FILE="/etc/steam-opt-marker"
declare -r CONFIG_VERSION="v6.2"
declare -r BACKUP_RETENTION=5

declare -r SWAP_SIZE_GB=20
declare -r SWAP_PATH="/home/swapfile"
declare -r SWAPPINESS=20

declare FAILED_COUNT=0
declare PASSED_COUNT=0

# ── Colours ────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ── Logging ─────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[*]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE" >&2; }

die() {
    error "$1"
    exit 1
}

# ── Read-only filesystem safety net (trap-based restore) ────────────
CLEANUP_NEEDED=false

restore_readonly() {
    if [[ "$CLEANUP_NEEDED" == "true" ]]; then
        echo -e "${YELLOW}[!]${NC} $(date '+%H:%M:%S') Restoring read-only filesystem..." | tee -a "$LOG_FILE"
        if command -v steamos-readonly &> /dev/null; then
            sudo steamos-readonly enable 2>/dev/null && \
                echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') Read-only filesystem restored" | tee -a "$LOG_FILE" || \
                warn "Could not restore read-only state (check manually: steamos-readonly status)"
        fi
        CLEANUP_NEEDED=false
    fi
}

trap 'restore_readonly' EXIT
trap 'restore_readonly; exit 130' INT
trap 'restore_readonly; exit 143' TERM

enable_writable() {
    if command -v steamos-readonly &> /dev/null; then
        if sudo steamos-readonly disable; then
            CLEANUP_NEEDED=true
            success "Write access granted"
        else
            die "Failed to disable read-only filesystem"
        fi
    else
        warn "steamos-readonly not found — assuming writable system"
    fi
}

# ── Backup helpers ──────────────────────────────────────────────────
backup_configs() {
    local backup_root="$1"
    mkdir -p "$backup_root/systemd"

    [[ -f /etc/default/grub ]] && cp /etc/default/grub "$backup_root/" && \
        log "Backed up /etc/default/grub"
    [[ -f /etc/fstab ]] && cp /etc/fstab "$backup_root/" && \
        log "Backed up /etc/fstab" || die "Cannot proceed without /etc/fstab"
    [[ -f /etc/sysctl.conf ]] && cp /etc/sysctl.conf "$backup_root/" && \
        log "Backed up /etc/sysctl.conf"
    cp /etc/systemd/system/*.service "$backup_root/systemd/" 2>/dev/null && \
        log "Backed up systemd service files"

    success "Configuration backup complete: $backup_root"
}

cleanup_old_backups() {
    local dirs
    dirs=$(find "$HOME" -maxdepth 1 -name 'steam-optim-backup-*' -type d 2>/dev/null | sort)
    local count
    count=$(echo "$dirs" | grep -c . 2>/dev/null || echo 0)

    if [[ "$count" -gt "$BACKUP_RETENTION" ]]; then
        echo "$dirs" | head -n $((count - BACKUP_RETENTION)) | while read -r old; do
            rm -rf "$old"
            log "Cleaned old backup: $old"
        done
    fi
}

# ── Marker management ───────────────────────────────────────────────
check_marker() {
    local mode="$1"

    if [[ ! -f "$MARKER_FILE" ]]; then
        return 1  # no marker — proceed
    fi

    local current_ver
    current_ver=$(sudo cat "$MARKER_FILE" 2>/dev/null || echo "unknown")

    if [[ "$current_ver" == "$CONFIG_VERSION" ]]; then
        if [[ "$mode" != "--reapply" ]]; then
            log "Already configured ($current_ver) — nothing to do"
            log "Use --reapply to force re-application"
            return 0  # up to date — skip
        fi
        warn "Reapply requested — proceeding"
        return 1
    fi

    warn "Marker version mismatch ($current_ver vs $CONFIG_VERSION) — proceeding"
    return 1
}

write_marker() {
    echo "$CONFIG_VERSION" | sudo tee "$MARKER_FILE" > /dev/null
    log "Configuration marker written: $CONFIG_VERSION"
}

# ════════════════════════════════════════════════════════════════════
# OPTIMIZATION FUNCTIONS
# ════════════════════════════════════════════════════════════════════

apply_cpu_governor() {
    log "Configuring CPU performance governor..."

    # Boot-time application
    sudo tee /etc/systemd/system/cpu-performance.service > /dev/null << 'SVCEOF'
[Unit]
Description=CPU Performance Governor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    # Gaming Mode re-application (NOW using graphical.target)
    sudo tee /etc/systemd/system/cpu-governor-gaming-hook.service > /dev/null << 'SVCEOF'
[Unit]
Description=Re-apply Performance Governor on Gaming Mode Start
After=graphical.target
PartOf=graphical.target

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do sleep 10; [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && break; done'
ExecStartPre=/bin/sleep 10
ExecStart=/bin/sh -c 'cpupower frequency-set -g performance; sleep 5; cpupower frequency-set -g performance'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable cpu-performance.service 2>/dev/null || \
        warn "Could not enable cpu-performance.service"
    sudo systemctl enable cpu-governor-gaming-hook.service 2>/dev/null || \
        warn "Could not enable cpu-governor-gaming-hook.service"

    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g performance 2>/dev/null && \
            success "CPU governor set to performance (now + boot + Gaming Mode)" || \
            warn "Immediate governor change failed — will apply at boot"
    else
        warn "cpupower not found — governor set at boot by service"
    fi
}

apply_cpu_monitor_service() {
    log "Adding CPU governor persistent monitor (60s polling)..."

    # Timer that wakes every 60 seconds
    sudo tee /etc/systemd/system/cpu-monitor.timer > /dev/null << 'SVCEOF'
[Unit]
Description=Timer to Check CPU Governor Periodically

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=1s

[Install]
WantedBy=timers.target
SVCEOF

    # Service that checks and restores if needed
    sudo tee /etc/systemd/system/cpu-monitor.service > /dev/null << 'SVCEOF'
[Unit]
Description=Check and Restore CPU Governor

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null); if [[ "$GOV" != "performance" ]]; then echo "CPU governor was $GOV, forcing performance"; cpupower frequency-set -g performance 2>/dev/null; fi'
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable cpu-monitor.timer 2>/dev/null || \
        warn "Could not enable cpu-monitor.timer"
    sudo systemctl start cpu-monitor.timer 2>/dev/null || \
        warn "Could not start cpu-monitor.timer"

    success "CPU governor monitor installed (checks every 60s)"
}

apply_memory_sysctl() {
    log "Configuring memory parameters..."

    sudo tee /etc/sysctl.d/99-steam-opt.conf > /dev/null << SVCEOF
# Gaming memory optimizations
vm.swappiness=${SWAPPINESS}
vm.vfs_cache_pressure=50
vm.min_free_kbytes=102400
SVCEOF

    sudo tee /etc/systemd/system/sysctl-gaming.service > /dev/null << 'SVCEOF'
[Unit]
Description=Gaming Sysctl Overrides
DefaultDependencies=no
Before=sysinit.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/sysctl -p /etc/sysctl.d/99-steam-opt.conf
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable sysctl-gaming.service 2>/dev/null || \
        warn "Could not enable sysctl-gaming.service"
    sudo sysctl -p /etc/sysctl.d/99-steam-opt.conf 2>/dev/null && \
        success "Memory sysctl configured" || \
        warn "Could not apply sysctl immediately"
}

apply_memlock_limits() {
    log "Configuring memlock limits..."

    sudo tee /etc/security/limits.d/99-steamos-memlock.conf > /dev/null << 'SVCEOF'
@users soft memlock 2147483648
@users hard memlock 2147483648
root soft memlock unlimited
root hard memlock unlimited
* soft memlock 2147483648
* hard memlock 2147483648
SVCEOF

    success "Memlock limits configured"
}

apply_swap_file() {
    log "Managing swap file..."

    local expected_bytes=$((SWAP_SIZE_GB * 1024 * 1024 * 1024))

    if [[ -f "$SWAP_PATH" ]]; then
        local current_size
        current_size=$(stat -c %s "$SWAP_PATH" 2>/dev/null || echo 0)

        if [[ "$current_size" -eq "$expected_bytes" ]]; then
            if sudo swapon --show 2>/dev/null | grep -q swapfile; then
                success "Swap file already active (${SWAP_SIZE_GB}GB)"
            else
                sudo swapon "$SWAP_PATH" && \
                    success "Swap file activated (${SWAP_SIZE_GB}GB)" || \
                    warn "Could not activate swap — check 'swapon ${SWAP_PATH}'"
            fi
            return 0
        else
            warn "Swap file wrong size (${current_size} bytes) — recreating"
            sudo swapoff "$SWAP_PATH" 2>/dev/null || true
            sudo rm -f "$SWAP_PATH"
        fi
    fi

    sudo sed -i '/swapfile/d' /etc/fstab 2>/dev/null || true

    if ! sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_PATH" 2>/dev/null; then
        warn "fallocate failed — falling back to dd (slow)"
        sudo dd if=/dev/zero of="$SWAP_PATH" bs=4M \
            count=$((SWAP_SIZE_GB * 256)) status=progress || die "Swap creation failed"
    fi

    sudo chmod 600 "$SWAP_PATH"
    sudo mkswap "$SWAP_PATH" > /dev/null || die "mkswap failed"

    # CORRECTED: use actual swap path, not hardcoded /swapfile
    echo "$SWAP_PATH none swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null

    sudo swapon "$SWAP_PATH" || die "swapon failed"
    success "Swap file created and active (${SWAP_SIZE_GB}GB)"
}

apply_thp() {
    log "Configuring Transparent Huge Pages..."

    # Boot-time application
    sudo tee /etc/systemd/system/thp.service > /dev/null << 'SVCEOF'
[Unit]
Description=Transparent Huge Pages Configuration
Before=basic.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    # Gaming Mode re-application (NOW using graphical.target)
    sudo tee /etc/systemd/system/thp-gaming-hook.service > /dev/null << 'SVCEOF'
[Unit]
Description=Re-apply THP Settings on Gaming Mode Start
After=graphical.target
PartOf=graphical.target

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do sleep 10; [ -f /sys/kernel/mm/transparent_hugepage/enabled ] && break; done'
ExecStartPre=/bin/sleep 10
ExecStart=/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
SVCEOF

    # Nuclear option: path-watcher that reverts ANY runtime change to THP
    sudo tee /etc/systemd/system/thp-watch.path > /dev/null << 'SVCEOF'
[Unit]
Description=Watch THP enabled Setting for Changes

[Path]
PathModified=/sys/kernel/mm/transparent_hugepage/enabled

[Install]
WantedBy=multi-user.target
SVCEOF

    sudo tee /etc/systemd/system/thp-watch.service > /dev/null << 'SVCEOF'
[Unit]
Description=Enforce THP madvise Setting

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 1; echo madvise > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable thp.service 2>/dev/null || warn "Could not enable thp.service"
    sudo systemctl enable thp-gaming-hook.service 2>/dev/null || \
        warn "Could not enable thp-gaming-hook.service"
    sudo systemctl enable --now thp-watch.path 2>/dev/null || \
        warn "Could not enable thp-watch.path (path watcher inactive)"

    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null 2>&1 || true
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null 2>&1 || true

    success "THP configured (boot + Gaming Mode + runtime enforcement)"
}

apply_mglru() {
    log "Checking MGLRU support..."

    if [[ ! -f /sys/kernel/mm/lru_gen/enabled ]]; then
        warn "MGLRU not supported on this kernel"
        return 0
    fi

    echo 7 | sudo tee /sys/kernel/mm/lru_gen/enabled > /dev/null
    echo 0 | sudo tee /sys/kernel/mm/lru_gen/min_ttl_ms > /dev/null 2>&1 || true

    sudo tee /etc/tmpfiles.d/mglru.conf > /dev/null << 'SVCEOF'
w /sys/kernel/mm/lru_gen/enabled - - - - 7
w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0
SVCEOF

    sudo systemd-tmpfiles --create /etc/tmpfiles.d/mglru.conf 2>/dev/null || true
    success "MGLRU enabled"
}

apply_kernel_params() {
    log "Configuring kernel boot parameters..."

    if grep -q "nowatchdog" /etc/default/grub 2>/dev/null; then
        log "Kernel params already configured"
    else
        sudo sed -i '/nmi_watchdog/d' /etc/default/grub 2>/dev/null || true

        if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nowatchdog nmi_watchdog=0"/' /etc/default/grub
            success "Updated GRUB cmdline"
        else
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog nmi_watchdog=0"' | \
                sudo tee -a /etc/default/grub > /dev/null
            success "Appended GRUB cmdline"
        fi
    fi

    # Auto-detect GRUB config location
    local grub_cfg=""
    local candidates=(
        "/boot/efi/EFI/steamos/grub.cfg"
        "/boot/efi/EFI/BOOT/grub.cfg"
        "/boot/efi/EFI/systemd/grub.cfg"
        "/boot/grub/grub.cfg"
        "/boot/grub2/grub.cfg"
    )

    for cfg in "${candidates[@]}"; do
        if [[ -f "$cfg" ]]; then
            grub_cfg="$cfg"
            break
        fi
    done

    if [[ -z "$grub_cfg" ]]; then
        # Last resort: hunt for any grub.cfg under /boot
        grub_cfg=$(sudo find /boot -name 'grub.cfg' 2>/dev/null | head -n 1)
    fi

    if [[ -n "$grub_cfg" ]]; then
        if sudo grub-mkconfig -o "$grub_cfg" > /dev/null 2>&1; then
            success "GRUB config updated: $grub_cfg — REBOOT REQUIRED"
        else
            warn "grub-mkconfig failed for $grub_cfg"
        fi
    else
        warn "No grub.cfg found anywhere under /boot — kernel params saved to /etc/default/grub but NOT loaded"
        warn "Locate manually: sudo find /boot -name '*.cfg' -o -name 'grub*'"
    fi
}

apply_io_scheduler() {
    log "Configuring I/O scheduler..."

    sudo tee /etc/udev/rules.d/99-nvme-scheduler.rules > /dev/null << 'SVCEOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
SVCEOF

    sudo tee /etc/systemd/system/nvme-scheduler.service > /dev/null << 'SVCEOF'
[Unit]
Description=Set NVMe I/O Scheduler to None
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for dev in /sys/block/nvme*/queue/scheduler; do echo none > "$dev" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=default.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable nvme-scheduler.service 2>/dev/null || \
        warn "Could not enable nvme-scheduler.service"

    for dev in /sys/block/nvme*/queue/scheduler; do
        [[ -e "$dev" ]] || continue
        echo none | sudo tee "$dev" > /dev/null 2>&1 || true
    done

    sudo udevadm control --reload-rules 2>/dev/null || true
    success "I/O scheduler configured"
}

apply_noatime() {
    log "Checking noatime configuration..."

    if mount | grep -q '/home.*noatime'; then
        log "/home already mounted with noatime"
        return 0
    fi

    if grep -q '/home' /etc/fstab; then
        if ! grep '/home' /etc/fstab | grep -q noatime; then
            sudo sed -i -E '/^[^#]*\/home/s/(defaults[^ ]*)/\1,noatime/' /etc/fstab
            success "Added noatime to /home in fstab"
        else
            log "fstab already has noatime for /home (takes effect next boot)"
        fi
    else
        warn "/home not in fstab — skipping noatime"
    fi
}

# ════════════════════════════════════════════════════════════════════
# VERIFICATION (FIXED — no duplicates, proper checks)
# ════════════════════════════════════════════════════════════════════

pass() { success "$1"; ((PASSED_COUNT++)); }
fail() { error "$1"; ((FAILED_COUNT++)); }

do_verify() {
    # Warm up sudo once so we don't prompt mid-report
    if ! sudo -v 2>/dev/null; then
        warn "Sudo unavailable — some checks may fail"
    fi

    echo ""
    echo "============================================"
    echo "  VERIFICATION REPORT"
    echo "============================================"

    # CPU Governor (FIXED — only check first CPU, not all)
    local gov
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null | head -n1)
    if [[ "$gov" == "performance" ]]; then
        pass "CPU Governor (performance)"
    else
        fail "CPU Governor (got: '$gov')"
    fi

    # Swap active
    sudo swapon --show 2>/dev/null | grep -q swapfile && \
        pass "Swap Active" || \
        fail "Swap Active (no swapfile in swapon output)"

    # Swap size
    if [[ -f "$SWAP_PATH" ]]; then
        local actual_gb=$(( $(stat -c %s "$SWAP_PATH") / 1024 / 1024 / 1024 ))
        [[ "$actual_gb" -ge "$SWAP_SIZE_GB" ]] && \
            pass "Swap Size (${actual_gb}GB)" || \
            fail "Swap Size (${actual_gb}GB, wanted ≥ ${SWAP_SIZE_GB}GB)"
    else
        fail "Swap Size (swapfile does not exist)"
    fi

    # THP — bracketed entry is ACTIVE mode
    local thp
    thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
    [[ "$thp" == *"[madvise]"* ]] && \
        pass "THP Mode (madvise)" || \
        fail "THP Mode (got: '$thp')"

    # MGLRU
    [[ "$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null)" == *0x* ]] && \
        pass "MGLRU Enabled" || \
        fail "MGLRU Enabled (got: '$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null)')"

    # noatime
    mount | grep -q '/home.*noatime' && \
        pass "noatime Mount" || \
        fail "noatime Mount (/home not mounted with noatime)"

    # Sysctl config
    [[ -f /etc/sysctl.d/99-steam-opt.conf ]] && \
        pass "Sysctl Config" || \
        fail "Sysctl Config (missing file)"

    # Services enabled
    local svc
    for svc in steam-machine-opt cpu-performance thp nvme-scheduler; do
        [[ "$(systemctl is-enabled "$svc.service" 2>/dev/null)" == "enabled" ]] && \
            pass "Service: $svc" || \
            fail "Service: $svc (not enabled)"
    done

    # Gaming Mode hooks (using graphical.target)
    for svc in cpu-governor-gaming-hook thp-gaming-hook; do
        local state
        state=$(systemctl is-enabled "$svc.service" 2>/dev/null)
        if [[ "$state" == "enabled" ]]; then
            pass "Gaming Hook: $svc"
        elif [[ "$state" == "not-found" ]]; then
            fail "Gaming Hook: $svc (service missing)"
        else
            fail "Gaming Hook: $svc (state: $state)"
        fi
    done

    # THP path watcher
    [[ "$(systemctl is-active thp-watch.path 2>/dev/null)" == "active" ]] && \
        pass "THP Runtime Watcher" || \
        fail "THP Runtime Watcher (not active)"

    # CPU monitor timer (NEW in v6.2)
    [[ "$(systemctl is-active cpu-monitor.timer 2>/dev/null)" == "active" ]] && \
        pass "CPU Monitor Timer (60s polling)" || \
        fail "CPU Monitor Timer (not active)"

    # Installed binary
    [[ -x /usr/local/bin/steammachine_opt.sh ]] && \
        pass "Binary Exists" || \
        fail "Binary Exists (missing)"

    echo ""
    echo "============================================"
    echo "  RESULT: $PASSED_COUNT passed, $FAILED_COUNT failed"
    echo "============================================"

    [[ $FAILED_COUNT -gt 0 ]] && warn "Failures detected — run --reapply to fix"
    return 0
}

# ════════════════════════════════════════════════════════════════════
# INSTALL + APPLY + MAIN
# ════════════════════════════════════════════════════════════════════

do_install() {
    echo ""
    echo "============================================"
    echo "  INSTALLING BOOT SERVICE"
    echo "============================================"

    enable_writable

    sudo mkdir -p /usr/local/bin
    sudo cp "$SCRIPT_PATH" /usr/local/bin/steammachine_opt.sh || \
        die "Copy to /usr/local/bin failed"
    sudo chmod +x /usr/local/bin/steammachine_opt.sh
    [[ -x /usr/local/bin/steammachine_opt.sh ]] || die "Binary install verification failed"
    success "Binary installed: /usr/local/bin/steammachine_opt.sh"

    sudo tee /etc/systemd/system/steam-machine-opt.service > /dev/null << 'EOF'
[Unit]
Description=Steam Machine Optimizer
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/steammachine_opt.sh --auto
StandardOutput=append:/var/log/steam-machine-opt.log
StandardError=append:/var/log/steam-machine-opt.err
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable steam-machine-opt.service || die "Failed to enable service"

    [[ "$(systemctl is-enabled steam-machine-opt.service 2>/dev/null)" == "enabled" ]] || \
        die "Post-install verification failed"
    success "Install verified (binary + service)"
}


# ════════════════════════════════════════════════════════════════════
# UNINSTALL — full teardown + config restoration from backup
# ════════════════════════════════════════════════════════════════════

do_uninstall() {
    echo ""
    echo "============================================"
    echo "  UNINSTALLING STEAM MACHINE OPTIMIZER"
    echo "============================================"

    enable_writable

    # Locate most recent backup
    local backup_dir
    backup_dir=$(find "$HOME" -maxdepth 1 -name 'steam-optim-backup-*' -type d 2>/dev/null | sort | tail -n 1)

    if [[ -n "$backup_dir" ]]; then
        echo -e "${YELLOW}Restoring configs from: $backup_dir${NC}"
        read -rp "Restore GRUB/fstab/sysctl from this backup? [y/N]: " confirm_restore
        if [[ "$confirm_restore" =~ ^[Yy]$ ]]; then
            [[ -f "$backup_dir/grub" ]] && sudo cp "$backup_dir/grub" /etc/default/grub && \
                log "Restored /etc/default/grub"
            [[ -f "$backup_dir/fstab" ]] && sudo cp "$backup_dir/fstab" /etc/fstab && \
                log "Restored /etc/fstab"
            [[ -f "$backup_dir/sysctl.conf" ]] && sudo cp "$backup_dir/sysctl.conf" /etc/sysctl.conf && \
                log "Restored /etc/sysctl.conf"

            # Regenerate GRUB so restored cmdline actually takes effect
            local grub_cfg=""
            local candidates=(
                "/boot/efi/EFI/steamos/grub.cfg"
                "/boot/efi/EFI/BOOT/grub.cfg"
                "/boot/efi/EFI/systemd/grub.cfg"
                "/boot/grub/grub.cfg"
                "/boot/grub2/grub.cfg"
            )
            for cfg in "${candidates[@]}"; do
                [[ -f "$cfg" ]] && grub_cfg="$cfg" && break
            done
            [[ -z "$grub_cfg" ]] && grub_cfg=$(sudo find /boot -name 'grub.cfg' 2>/dev/null | head -n 1)
            [[ -n "$grub_cfg" ]] && sudo grub-mkconfig -o "$grub_cfg" > /dev/null 2>&1 && \
                success "GRUB config regenerated from restored defaults"
        else
            warn "Skipping config restore — optimizer-edited configs left in place"
            warn "Remove GRUB kernel params manually if desired: nowatchdog nmi_watchdog=0"
        fi
    else
        warn "No backup directory found — cannot restore configs"
        warn "Manually revert: remove 'nowatchdog nmi_watchdog=0' from /etc/default/grub"
    fi

    # Tear down every unit this script created
    local units=(
        steam-machine-opt.service
        cpu-performance.service
        cpu-governor-gaming-hook.service
        cpu-monitor.timer
        cpu-monitor.service
        sysctl-gaming.service
        thp.service
        thp-gaming-hook.service
        thp-watch.path
        thp-watch.service
        nvme-scheduler.service
    )

    for unit in "${units[@]}"; do
        sudo systemctl disable --now "$unit" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$unit"
    done
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    success "All services, hooks, timers, and watchers removed"

    # Config files created by the script
    sudo rm -f /etc/sysctl.d/99-steam-opt.conf
    sudo rm -f /etc/security/limits.d/99-steamos-memlock.conf
    sudo rm -f /etc/tmpfiles.d/mglru.conf
    sudo rm -f /etc/udev/rules.d/99-nvme-scheduler.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    log "Removed config files (sysctl.d, limits.d, tmpfiles.d, udev rule)"

    # Swap file: off + remove + strip fstab line
    if [[ -f "$SWAP_PATH" ]]; then
        read -rp "Also delete the ${SWAP_SIZE_GB}GB swap file ($SWAP_PATH)? [y/N]: " confirm_swap
        if [[ "$confirm_swap" =~ ^[Yy]$ ]]; then
            sudo swapoff "$SWAP_PATH" 2>/dev/null || true
            sudo rm -f "$SWAP_PATH"
            sudo sed -i '/swapfile/d' /etc/fstab
            success "Swap file removed and fstab cleaned"
        else
            sudo sed -i '/swapfile/d' /etc/fstab
            warn "Swap file left on disk but fstab entry removed"
        fi
    fi

    # Binary + marker + logs
    sudo rm -f /usr/local/bin/steammachine_opt.sh
    sudo rm -f "$MARKER_FILE"
    rm -f /tmp/steam-machine-opt-*.log
    log "Removed binary, marker, and logs"

    # Return runtime settings to SteamOS defaults immediately
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g schedutil 2>/dev/null && \
            log "CPU governor restored to schedutil" || \
            warn "Could not reset governor — default resumes after reboot"
    fi
    sudo sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null' || true
    sudo sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null' || true
    sudo sysctl vm.swappiness=60 vm.vfs_cache_pressure=100 2>/dev/null || true
    log "Runtime settings returned to kernel/SteamOS defaults"

    restore_readonly

    echo ""
    success "Uninstall complete. Reboot to settle everything back to stock."
    echo ""
    echo "Backups intentionally KEPT at: $HOME/steam-optim-backup-*"
    echo "Delete them manually once you're satisfied everything is back to normal."
}


# ════════════════════════════════════════════════════════════════════
# UNINSTALL — full teardown + config restoration from backup
# ════════════════════════════════════════════════════════════════════

do_uninstall() {
    echo ""
    echo "============================================"
    echo "  UNINSTALLING STEAM MACHINE OPTIMIZER"
    echo "============================================"

    enable_writable

    # Locate most recent backup
    local backup_dir
    backup_dir=$(find "$HOME" -maxdepth 1 -name 'steam-optim-backup-*' -type d 2>/dev/null | sort | tail -n 1)

    if [[ -n "$backup_dir" ]]; then
        echo -e "${YELLOW}Restoring configs from: $backup_dir${NC}"
        read -rp "Restore GRUB/fstab/sysctl from this backup? [y/N]: " confirm_restore
        if [[ "$confirm_restore" =~ ^[Yy]$ ]]; then
            [[ -f "$backup_dir/grub" ]] && sudo cp "$backup_dir/grub" /etc/default/grub && \
                log "Restored /etc/default/grub"
            [[ -f "$backup_dir/fstab" ]] && sudo cp "$backup_dir/fstab" /etc/fstab && \
                log "Restored /etc/fstab"
            [[ -f "$backup_dir/sysctl.conf" ]] && sudo cp "$backup_dir/sysctl.conf" /etc/sysctl.conf && \
                log "Restored /etc/sysctl.conf"

            # Regenerate GRUB so restored cmdline actually takes effect
            local grub_cfg=""
            local candidates=(
                "/boot/efi/EFI/steamos/grub.cfg"
                "/boot/efi/EFI/BOOT/grub.cfg"
                "/boot/efi/EFI/systemd/grub.cfg"
                "/boot/grub/grub.cfg"
                "/boot/grub2/grub.cfg"
            )
            for cfg in "${candidates[@]}"; do
                [[ -f "$cfg" ]] && grub_cfg="$cfg" && break
            done
            [[ -z "$grub_cfg" ]] && grub_cfg=$(sudo find /boot -name 'grub.cfg' 2>/dev/null | head -n 1)
            [[ -n "$grub_cfg" ]] && sudo grub-mkconfig -o "$grub_cfg" > /dev/null 2>&1 && \
                success "GRUB config regenerated from restored defaults"
        else
            warn "Skipping config restore — optimizer-edited configs left in place"
            warn "Remove GRUB kernel params manually if desired: nowatchdog nmi_watchdog=0"
        fi
    else
        warn "No backup directory found — cannot restore configs"
        warn "Manually revert: remove 'nowatchdog nmi_watchdog=0' from /etc/default/grub"
    fi

    # Tear down every unit this script created
    local units=(
        steam-machine-opt.service
        cpu-performance.service
        cpu-governor-gaming-hook.service
        cpu-monitor.timer
        cpu-monitor.service
        sysctl-gaming.service
        thp.service
        thp-gaming-hook.service
        thp-watch.path
        thp-watch.service
        nvme-scheduler.service
    )

    for unit in "${units[@]}"; do
        sudo systemctl disable --now "$unit" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$unit"
    done
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    success "All services, hooks, timers, and watchers removed"

    # Config files created by the script
    sudo rm -f /etc/sysctl.d/99-steam-opt.conf
    sudo rm -f /etc/security/limits.d/99-steamos-memlock.conf
    sudo rm -f /etc/tmpfiles.d/mglru.conf
    sudo rm -f /etc/udev/rules.d/99-nvme-scheduler.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    log "Removed config files (sysctl.d, limits.d, tmpfiles.d, udev rule)"

    # Swap file: off + remove + strip fstab line
    if [[ -f "$SWAP_PATH" ]]; then
        read -rp "Also delete the ${SWAP_SIZE_GB}GB swap file ($SWAP_PATH)? [y/N]: " confirm_swap
        if [[ "$confirm_swap" =~ ^[Yy]$ ]]; then
            sudo swapoff "$SWAP_PATH" 2>/dev/null || true
            sudo rm -f "$SWAP_PATH"
            sudo sed -i '/swapfile/d' /etc/fstab
            success "Swap file removed and fstab cleaned"
        else
            sudo sed -i '/swapfile/d' /etc/fstab
            warn "Swap file left on disk but fstab entry removed"
        fi
    fi

    # Binary + marker + logs
    sudo rm -f /usr/local/bin/steammachine_opt.sh
    sudo rm -f "$MARKER_FILE"
    rm -f /tmp/steam-machine-opt-*.log
    log "Removed binary, marker, and logs"

    # Return runtime settings to SteamOS defaults immediately
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g schedutil 2>/dev/null && \
            log "CPU governor restored to schedutil" || \
            warn "Could not reset governor — default resumes after reboot"
    fi
    sudo sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null' || true
    sudo sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null' || true
    sudo sysctl vm.swappiness=60 vm.vfs_cache_pressure=100 2>/dev/null || true
    log "Runtime settings returned to kernel/SteamOS defaults"

    restore_readonly

    echo ""
    success "Uninstall complete. Reboot to settle everything back to stock."
    echo ""
    echo "Backups intentionally KEPT at: $HOME/steam-optim-backup-*"
    echo "Delete them manually once you're satisfied everything is back to normal."
}

do_apply() {
    local mode="$1"

    log "Starting optimization (mode: $mode)"

    enable_writable

    local backup_dir="$HOME/steam-optim-backup-$(date +%Y%m%d-%H%M%S)"
    backup_configs "$backup_dir"
    cleanup_old_backups

    apply_cpu_governor
    apply_cpu_monitor_service  # ← NEW in v6.2
    apply_memory_sysctl
    apply_memlock_limits
    apply_swap_file
    apply_thp
    apply_mglru
    apply_kernel_params
    apply_io_scheduler
    apply_noatime

    write_marker

    do_verify

    echo ""
    echo "============================================"
    echo "  OPTIMIZATION COMPLETE ($CONFIG_VERSION)"
    echo "============================================"
    echo ""
    echo "  • CPU → performance (boot + Gaming Mode + 60s monitor)"
    echo "  • Memory → swappiness ${SWAPPINESS}, vfs 50, min_free 100MB"
    echo "  • Swap → ${SWAP_SIZE_GB}GB at $SWAP_PATH"
    echo "  • THP → madvise (boot + Gaming Mode + runtime watcher)"
    echo "  • MGLRU → enabled"
    echo "  • Kernel → watchdogs off (REBOOT REQUIRED)"
    echo "  • I/O → NVMe scheduler none"
    echo "  • noatime → /home"
    echo ""
    echo "Backup: $backup_dir"
    echo "Log:    $LOG_FILE"
    echo "Marker: $MARKER_FILE"
    echo ""

    if [[ "$mode" != "--auto" && "$mode" != "--install" ]]; then
        read -rp "Press Enter to exit..."
    fi
}

main() {
    local mode="${1:-}"

    case "$mode" in
        --verify)
            do_verify
            ;;
        --install)
            echo ""
            echo -e "${YELLOW}This installs the boot service AND applies all optimizations.${NC}"
            read -rp "Continue? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted by user"; exit 0; }
            do_install
            do_apply "--install"
            ;;
        --run|--auto)
            [[ "$mode" == "--run" ]] && {
                echo ""
                echo -e "${YELLOW}This modifies GRUB, sysctl, systemd, fstab and swap config.${NC}"
                echo -e "${RED}A reboot is required for kernel parameters.${NC}"
                echo ""
                read -rp "Continue? [y/N]: " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted by user"; exit 0; }
            }
            check_marker "$mode" || do_apply "$mode"
            ;;
        --uninstall)
            echo ""
            echo -e "${RED}This removes ALL optimizations and restores backed-up configs.${NC}"
            read -rp "Continue? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted by user"; exit 0; }
            do_uninstall
            ;;
        --uninstall)
            echo ""
            echo -e "${RED}This removes ALL optimizations and restores backed-up configs.${NC}"
            read -rp "Continue? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted by user"; exit 0; }
            do_uninstall
            ;;
        --reapply)
            sudo rm -f "$MARKER_FILE"
            do_apply "$mode"
            ;;
        *)
            echo ""
            echo "============================================"
            echo "  STEAM MACHINE OPTIMIZER $CONFIG_VERSION"
            echo "============================================"
            echo ""
            echo "Usage:"
            echo "  $SCRIPT_NAME --install   Install boot service + apply"
            echo "  $SCRIPT_NAME --run       Interactive optimization"
            echo "  $SCRIPT_NAME --auto      Unattended (systemd)"
            echo "  $SCRIPT_NAME --verify    Check current state"
            echo "  $SCRIPT_NAME --reapply   Force re-apply"
            echo "  $SCRIPT_NAME --uninstall Remove all, restore from backup"
            echo "  $SCRIPT_NAME --uninstall Remove all, restore from backup"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
