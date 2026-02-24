#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  aix_emu.sh — AIX Command Emulator for WSL / Linux
#  Author: AIX SRE Harry Joseph
#
#  USAGE:
#    source ~/aix_emu.sh          # Load for current session
#
#  TO MAKE PERMANENT (auto-load every WSL session):
#    echo "source ~/aix_emu.sh" >> ~/.bashrc
#
#  HOW IT WORKS:
#    - AIX commands that are IDENTICAL on Linux → pass through unchanged
#    - AIX-UNIQUE commands → silently run the Linux equivalent
#    - Each translation prints a one-line banner so you learn the mapping
# ═══════════════════════════════════════════════════════════════════

_aix_banner() {
    echo -e "\e[36m── [AIX: $1  →  Linux: $2] \e[0m"
}

_aix_stub() {
    echo -e "\e[33m── [AIX: $1 → STUB: not available in WSL — concept shown below] \e[0m"
}

# ── Colour helpers (from aix_launch.sh pattern) ─────────────────
_info()  { echo -e "\e[36m[INFO]\e[0m  $*"; }
_ok()    { echo -e "\e[32m[ OK ]\e[0m  $*"; }
_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
_error() { echo -e "\e[31m[ERR ]\e[0m  $*"; }

# ── Pre-flight: check for missing tools on source ────────────────
_aix_preflight() {
    command -v nmon     &>/dev/null || _warn "nmon not installed — run: sudo apt install nmon"
    command -v whiptail &>/dev/null || _warn "whiptail missing — smit/smitty unavailable. Run: sudo apt install whiptail"
    command -v tmux     &>/dev/null || _warn "tmux missing — aix_launch.sh won't work. Run: sudo apt install tmux"
}
_aix_preflight

# ───────────────────────────────────────────────
#  LVM / STORAGE
# ───────────────────────────────────────────────

lspv() {
    # AIX: list physical volumes   Linux: lsblk
    _aix_banner "lspv" "lsblk"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null
}

lsvg() {
    if [[ "$1" == "-l" ]]; then
        # AIX: lsvg -l rootvg   Linux: lvdisplay
        _aix_banner "lsvg -l $2" "lvdisplay"
        sudo lvdisplay 2>/dev/null || echo "[INFO] LVM2 tools not installed — run: sudo apt install lvm2"
    else
        # AIX: lsvg   Linux: vgdisplay
        _aix_banner "lsvg" "vgdisplay"
        sudo vgdisplay 2>/dev/null || echo "[INFO] LVM2 tools not installed — run: sudo apt install lvm2"
    fi
}

lsfs() {
    # AIX: list filesystems   Linux: mount
    _aix_banner "lsfs" "mount | column -t"
    mount | column -t
}

# Override df to handle AIX's -g (gigabytes) flag
df() {
    if [[ "$*" == *"-g"* ]]; then
        _aix_banner "df -g" "df -h"
        command df -h "${@/-g/}"
    else
        command df "$@"
    fi
}

mklv() {
    # AIX: mklv -t jfs2 -y datalv rootvg 1   Linux: lvcreate
    _aix_banner "mklv" "lvcreate"
    echo "Usage (Linux equivalent):"
    echo "  sudo lvcreate -L <size>G -n <lvname> <vgname>"
    echo "  e.g. sudo lvcreate -L 10G -n datalv ubuntu-vg"
    if [[ -n "$*" ]]; then
        echo ""
        echo "[INFO] LVM2 required — run: sudo apt install lvm2"
        sudo lvcreate "$@" 2>/dev/null || echo "[HINT] Try: sudo lvcreate -L 1G -n mylv vgname"
    fi
}

rmlv() {
    # AIX: rmlv loglv   Linux: lvremove
    _aix_banner "rmlv $1" "sudo lvremove $1"
    if [[ -z "$1" ]]; then echo "Usage: rmlv <lvname>"; return 1; fi
    sudo lvremove "/dev/$1" 2>/dev/null || sudo lvremove "$1" 2>/dev/null || \
        echo "[ERROR] LV '$1' not found. Use 'lsvg -l' to list logical volumes."
}

chlv() {
    # AIX: chlv -n newname oldname   Linux: lvrename
    _aix_banner "chlv $*" "sudo lvrename / lvchange"
    echo "Common chlv equivalents:"
    echo "  Rename:  sudo lvrename <vgname> <old_lv> <new_lv>"
    echo "  Resize:  sudo lvextend -L +<size>G /dev/<vg>/<lv>"
    echo "           sudo resize2fs /dev/<vg>/<lv>"
}

crfs() {
    # AIX: crfs -v jfs2 -d datalv -m /data   Linux: mkfs + mount
    _aix_banner "crfs" "mkfs.ext4 + mount"
    echo "Usage (Linux equivalent):"
    echo "  sudo mkfs.ext4 /dev/<vg>/<lv>          # create filesystem"
    echo "  sudo mkdir -p /mountpoint"
    echo "  sudo mount /dev/<vg>/<lv> /mountpoint"
    echo "  echo '/dev/<vg>/<lv> /mountpoint ext4 defaults 0 2' | sudo tee -a /etc/fstab"
}

chfs() {
    # AIX: chfs -a size=+100M /data   Linux: lvextend + resize2fs
    _aix_banner "chfs -a size=$2 $3" "lvextend + resize2fs"
    echo "Usage (Linux equivalent — extend a mounted filesystem):"
    echo "  sudo lvextend -L +<size>G /dev/<vg>/<lv>"
    echo "  sudo resize2fs /dev/<vg>/<lv>        # ext4"
    echo "  sudo xfs_growfs /mountpoint          # xfs"
}

rmfs() {
    # AIX: rmfs /data   Linux: umount + lvremove
    _aix_banner "rmfs $1" "umount + lvremove"
    if [[ -z "$1" ]]; then echo "Usage: rmfs <mountpoint>"; return 1; fi
    echo "[WARN] This will unmount '$1' and remove its LV. Steps:"
    echo "  1. sudo umount $1"
    echo "  2. Remove /etc/fstab entry for $1"
    echo "  3. sudo lvremove /dev/<vg>/<lv>"
}

# ── Paging / Swap ────────────────────────────────
lspaging() {
    # AIX: lspaging   Linux: swapon -s
    _aix_banner "lspaging" "swapon --show + free -h"
    echo "=== Active Swap / Paging Spaces ==="
    swapon --show 2>/dev/null || cat /proc/swaps
    echo ""
    free -h | grep -E "Swap|Mem"
}

mkps() {
    # AIX: mkps -a -s 1 -n -t lv rootvg   Linux: fallocate + mkswap + swapon
    _aix_banner "mkps" "fallocate + mkswap + swapon"
    local size="${1:-2G}"
    local file="${2:-/swapfile2}"
    echo "Creating ${size} swap file at ${file}..."
    sudo fallocate -l "$size" "$file" && \
    sudo chmod 600 "$file" && \
    sudo mkswap "$file" && \
    sudo swapon "$file" && \
    echo "[OK] Swap active. Add to /etc/fstab to persist:"
    echo "  $file none swap sw 0 0" || \
    echo "[ERROR] Failed to create swap. Usage: mkps <size e.g. 2G> <file e.g. /swapfile2>"
}

rmps() {
    # AIX: rmps paging00   Linux: swapoff + rm
    _aix_banner "rmps $1" "swapoff + rm"
    if [[ -z "$1" ]]; then echo "Usage: rmps <swapfile or device>"; return 1; fi
    sudo swapoff "$1" 2>/dev/null && echo "[OK] Swap deactivated: $1" || echo "[ERROR] Could not deactivate $1"
    echo "[INFO] Remove /etc/fstab entry for $1 manually if present."
}

# ───────────────────────────────────────────────
#  AIX ERROR REPORTING
# ───────────────────────────────────────────────

errpt() {
    case "$1" in
        -a)
            _aix_banner "errpt -a" "journalctl -p err + dmesg"
            echo "=== Kernel Errors (dmesg) ==="
            dmesg --level=err,crit 2>/dev/null | tail -20 || dmesg | grep -iE "error|fail" | tail -20
            echo ""
            echo "=== System Journal Errors ==="
            journalctl -p err --no-pager -n 20 2>/dev/null || echo "[INFO] journalctl not available"
            ;;
        -d)
            case "$2" in
                H)
                    _aix_banner "errpt -d H" "dmesg (hardware errors)"
                    dmesg | grep -iE "hardware|disk|ata|scsi|nvme|i/o error" | tail -30
                    ;;
                S)
                    _aix_banner "errpt -d S" "journalctl -p err (software errors)"
                    journalctl -p err --no-pager -n 30 2>/dev/null || \
                        grep -iE "error|fail|kernel" /var/log/syslog 2>/dev/null | tail -30
                    ;;
                *)
                    echo "Usage: errpt -d H   (hardware)   or   errpt -d S   (software)"
                    ;;
            esac
            ;;
        -j)
            _aix_banner "errpt -j $2" "journalctl GREP: $2"
            journalctl --no-pager 2>/dev/null | grep -i "$2" | head -20 || \
                dmesg | grep -i "$2" | head -20
            ;;
        *)
            _aix_banner "errpt" "dmesg errors + journal summary"
            echo "=== Recent Kernel Messages (dmesg errors) ==="
            dmesg --level=err,crit,warn 2>/dev/null | tail -15 || dmesg | tail -15
            echo ""
            echo "=== Last 10 System Errors (journal) ==="
            journalctl -p err --no-pager -n 10 2>/dev/null || \
                grep -iE "error|fail" /var/log/syslog 2>/dev/null | tail -10
            ;;
    esac
}

errclear() {
    # AIX: errclear 0  →  clears ALL entries from the error log
    # AIX: errclear -d H 0  →  clears hardware entries only
    # Linux equivalent: journalctl vacuum + dmesg is read-only (kernel ring buffer)
    local days="${1:-0}"
    local dtype="${3:-}"
    if [[ "$1" == "-d" ]]; then
        _aix_banner "errclear -d $2 $3" "journalctl --vacuum-time"
        echo "[INFO] Clearing $2-class errors older than ${3:-all} entries..."
        sudo journalctl --rotate 2>/dev/null && \
            sudo journalctl --vacuum-time=1s 2>/dev/null && \
            _ok "Error log cleared (class: $2)." || \
            _warn "Could not clear journal — try: sudo journalctl --vacuum-time=1s"
    elif [[ "$days" == "0" ]]; then
        _aix_banner "errclear 0" "journalctl --vacuum-time=1s (clear all)"
        echo "[INFO] Clearing all system journal errors..."
        sudo journalctl --rotate 2>/dev/null && \
            sudo journalctl --vacuum-time=1s 2>/dev/null && \
            _ok "Error log cleared successfully." || \
            _warn "Could not clear journal — try: sudo journalctl --vacuum-time=1s"
    else
        _aix_banner "errclear $days" "journalctl --vacuum-time=${days}d"
        sudo journalctl --vacuum-time="${days}d" 2>/dev/null && \
            _ok "Entries older than ${days} day(s) cleared." || \
            _warn "Could not vacuum journal."
    fi
}

# ───────────────────────────────────────────────
#  PERFORMANCE MONITORING
# ───────────────────────────────────────────────

nmon() {
    # AIX: nmon (IBM's interactive performance monitor)
    # Modes:
    #   nmon            → interactive ncurses GUI (graphical menu)
    #   nmon -f         → capture/batch mode, writes .nmon file (no GUI)
    #   nmon -c -m -d   → launch GUI with CPU, Memory, Disk panels pre-opened
    #   nmon -h         → full help
    #   nmon -?         → quick reference hint
    #
    # NOTE: In Linux nmon, -c means "count" (batch iterations), NOT "CPU panel".
    #       Panel pre-selection is done via the NMON env variable internally.
    #       This wrapper maps -c/-m/-d/etc. flags to the correct NMON= method.

    if ! command -v nmon &>/dev/null; then
        if command -v htop &>/dev/null; then
            _aix_banner "nmon" "htop  (install nmon for AIX experience: sudo apt install nmon)"
            htop
        else
            _aix_banner "nmon" "top  (install nmon for AIX experience: sudo apt install nmon)"
            top
        fi
        return
    fi

    # Batch/passthrough mode — let nmon handle it directly
    if [[ " $* " == *" -f "* ]] || [[ "$*" == *"-f"* ]]; then
        command nmon "$@"
        return
    fi

    # Interactive mode — map panel flags to NMON env variable
    # so panels open immediately on launch (same behaviour as AIX)
    local panel_keys=""
    for arg in "$@"; do
        case "$arg" in
            -c|c) panel_keys+="c" ;;   # CPU
            -m|m) panel_keys+="m" ;;   # Memory
            -d|d) panel_keys+="d" ;;   # Disk
            -n|n) panel_keys+="n" ;;   # Network
            -N|N) panel_keys+="N" ;;   # NFS
            -t|t) panel_keys+="t" ;;   # Top processes
            -k|k) panel_keys+="k" ;;   # Kernel
            -r|r) panel_keys+="r" ;;   # Resource
            -j|j) panel_keys+="j" ;;   # File Systems
            -V|V) panel_keys+="V" ;;   # Virtual memory
            -\?|-h) command nmon "$arg"; return ;;
        esac
    done

    if [[ -n "$panel_keys" ]]; then
        NMON="$panel_keys" command nmon
    else
        command nmon
    fi
}

svmon() {
    case "$1" in
        -G)
            _aix_banner "svmon -G" "free -h + vmstat -s"
            echo "=== Memory Summary ==="
            free -h
            echo ""
            echo "=== Virtual Memory Stats ==="
            vmstat -s | head -15
            ;;
        -P)
            _aix_banner "svmon -P $2" "cat /proc/$2/status"
            if [[ -n "$2" && -f "/proc/$2/status" ]]; then
                grep -E "Name|VmRSS|VmSize|VmSwap|VmPeak" "/proc/$2/status"
            else
                echo "[ERROR] PID '$2' not found. Usage: svmon -P <pid>"
                echo "Tip: Use 'ps -ef | grep yourapp' to find the PID first."
            fi
            ;;
        *)
            _aix_banner "svmon" "free -h"
            free -h
            ;;
    esac
}

# ───────────────────────────────────────────────
#  AIX NETWORK
# ───────────────────────────────────────────────

entstat() {
    # AIX: entstat -all en0   Linux: ip -s link show eth0
    local iface="${2:-$(ip route | grep default | awk '{print $5}' | head -1)}"
    _aix_banner "entstat -all ${iface}" "ip -s link show ${iface}"
    ip -s link show "$iface" 2>/dev/null || ip -s link
}

no() {
    # AIX: no -o (network options)   Linux: sysctl net.*
    if [[ "$1" == "-o" ]]; then
        _aix_banner "no -o" "sysctl -a | grep net."
        sysctl -a 2>/dev/null | grep "^net\." | head -40
    else
        echo "Usage: no -o    (list network tuning parameters)"
    fi
}

# ───────────────────────────────────────────────
#  USER MANAGEMENT
# ───────────────────────────────────────────────

lsuser() {
    # AIX: lsuser ALL   Linux: parse /etc/passwd
    _aix_banner "lsuser ALL" "awk /etc/passwd"
    printf "%-20s %-8s %-8s %s\n" "USERNAME" "UID" "GID" "HOME"
    printf "%-20s %-8s %-8s %s\n" "--------" "---" "---" "----"
    awk -F: '{printf "%-20s %-8s %-8s %s\n", $1, $3, $4, $6}' /etc/passwd
}

mkuser() {
    # AIX: mkuser username   Linux: useradd username
    _aix_banner "mkuser $1" "useradd $1"
    sudo useradd "$1" && echo "[OK] User '$1' created." || echo "[ERROR] Failed to create user '$1'."
}

chuser() {
    # AIX: chuser account_locked=false username
    # AIX: chuser account_locked=true  username
    # Parses AIX-style key=value attribute assignments
    local attr="" val="" username=""
    for arg in "$@"; do
        if [[ "$arg" == *"="* ]]; then
            attr="${arg%%=*}"
            val="${arg#*=}"
        else
            username="$arg"
        fi
    done

    if [[ -z "$username" ]]; then
        echo "Usage: chuser account_locked=false <username>"
        echo "       chuser account_locked=true  <username>"
        return 1
    fi

    case "$attr" in
        account_locked)
            if [[ "$val" == "false" ]]; then
                _aix_banner "chuser account_locked=false $username" "faillock --reset + passwd -u"
                echo "=== Resetting failed login counter ==="
                sudo faillock --user "$username" --reset 2>/dev/null && \
                    echo "[OK] faillock reset for '$username'" || \
                    echo "[INFO] faillock not available (older system — trying pam_tally2)"
                sudo pam_tally2 --user="$username" --reset 2>/dev/null || true
                echo ""
                echo "=== Unlocking password ==="
                sudo passwd -u "$username" 2>/dev/null || sudo usermod -U "$username"
                echo "[OK] User '$username' unlocked."
            elif [[ "$val" == "true" ]]; then
                _aix_banner "chuser account_locked=true $username" "passwd -l + usermod -L"
                sudo passwd -l "$username" 2>/dev/null || sudo usermod -L "$username"
                echo "[OK] User '$username' locked."
            else
                echo "[ERROR] Unknown value: $val  (use true or false)"
            fi
            ;;
        expires)
            _aix_banner "chuser expires=$val $username" "sudo chage -E $val $username"
            sudo chage -E "$val" "$username"
            ;;
        maxage)
            _aix_banner "chuser maxage=$val $username" "sudo chage -M $val $username"
            sudo chage -M "$val" "$username"
            ;;
        groups)
            _aix_banner "chuser groups=$val $username" "sudo usermod -G $val $username"
            sudo usermod -G "$val" "$username"
            ;;
        *)
            echo "[INFO] Supported attributes: account_locked, expires, maxage, groups"
            echo "Usage examples:"
            echo "  chuser account_locked=false $username"
            echo "  chuser account_locked=true  $username"
            echo "  chuser maxage=90            $username"
            ;;
    esac
}

# ───────────────────────────────────────────────
#  DEVICE MANAGEMENT
# ───────────────────────────────────────────────

lsdev() {
    # AIX: lsdev   Linux: lshw or lspci
    _aix_banner "lsdev" "lshw -short / lspci"
    if command -v lshw &>/dev/null; then
        sudo lshw -short 2>/dev/null
    elif command -v lspci &>/dev/null; then
        lspci
    else
        echo "[INFO] Install lshw: sudo apt install lshw"
        ls /dev
    fi
}

cfgmgr() {
    # AIX: cfgmgr (configure devices)   Linux: udevadm trigger
    _aix_banner "cfgmgr" "udevadm trigger"
    sudo udevadm trigger 2>/dev/null && echo "[OK] Device configuration refreshed."
}

lsattr() {
    # AIX: lsattr -El sys0 / lsattr -El hdisk0   Linux: udevadm info
    local dev="${2:-sys0}"
    _aix_banner "lsattr -El $dev" "udevadm info + lshw"
    if command -v udevadm &>/dev/null; then
        local devpath
        devpath=$(find /dev -name "$dev" 2>/dev/null | head -1)
        if [[ -n "$devpath" ]]; then
            udevadm info --query=all --name="$devpath" 2>/dev/null
        else
            echo "=== System Attributes (uname -a + /proc/cpuinfo) ==="
            uname -a
            echo ""
            grep -E "model name|cpu MHz|cache size|siblings|cpu cores" /proc/cpuinfo 2>/dev/null | sort -u
        fi
    else
        echo "[INFO] Install udev: sudo apt install udev"
    fi
}

chdev() {
    # AIX: chdev -l en0 -a speed=100   Linux: ip link set
    _aix_banner "chdev $*" "ip link set / sysctl"
    echo "Common chdev equivalents:"
    echo "  Network speed/mtu:  sudo ip link set <iface> mtu 9000"
    echo "  Interface up/down:  sudo ip link set <iface> up|down"
    echo "  IP address:         sudo ip addr add <ip/prefix> dev <iface>"
}

lspath() {
    # AIX: lspath (multipath device paths)   Linux: multipath -l
    _aix_banner "lspath" "multipath -l"
    if command -v multipath &>/dev/null; then
        sudo multipath -l 2>/dev/null
    else
        echo "[INFO] multipath-tools not installed."
        echo "  Run: sudo apt install multipath-tools"
        echo ""
        echo "=== Block device paths (lsblk) ==="
        lsblk -o NAME,TYPE,SIZE,TRAN,MODEL 2>/dev/null
    fi
}

bosboot() {
    # AIX: bosboot -ad /dev/hdisk0   Linux: update-grub / grub-install
    _aix_banner "bosboot" "update-grub / grub-install"
    echo "=== Updating boot loader (Linux equivalent of bosboot) ==="
    if command -v update-grub &>/dev/null; then
        sudo update-grub 2>/dev/null && echo "[OK] Boot loader updated."
    elif command -v grub2-mkconfig &>/dev/null; then
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null && echo "[OK] GRUB2 config updated."
    else
        echo "[INFO] Run: sudo grub-install <device> && sudo update-grub"
    fi
}

# ───────────────────────────────────────────────
#  SOFTWARE MANAGEMENT (AIX: lslpp / installp)
# ───────────────────────────────────────────────

lslpp() {
    # AIX: lslpp -l (list installed filesets)   Linux: dpkg -l
    case "$1" in
        -l)
            _aix_banner "lslpp -l $2" "dpkg -l $2"
            if [[ -n "$2" ]]; then
                dpkg -l "*${2}*" 2>/dev/null
            else
                dpkg -l 2>/dev/null | less
            fi
            ;;
        -f)
            _aix_banner "lslpp -f $2" "dpkg -L $2"
            dpkg -L "$2" 2>/dev/null || echo "[ERROR] Package '$2' not found."
            ;;
        -h)
            _aix_banner "lslpp -h" "dpkg --list (history)"
            grep " install \| upgrade " /var/log/dpkg.log 2>/dev/null | tail -30 || \
                cat /var/log/apt/history.log 2>/dev/null | tail -40
            ;;
        *)
            _aix_banner "lslpp" "dpkg -l"
            dpkg -l 2>/dev/null | grep -v "^rc" | less
            ;;
    esac
}

installp() {
    # AIX: installp -aXd /path/to/pkg fileset   Linux: apt install
    _aix_banner "installp $*" "sudo apt install"
    local pkg=""
    for arg in "$@"; do
        [[ "$arg" != -* ]] && pkg="$arg"
    done
    if [[ -z "$pkg" ]]; then
        echo "Usage: installp -aXd <source> <package>"
        echo "Linux: sudo apt install <package>"
        return 1
    fi
    sudo apt install -y "$pkg"
}

# ───────────────────────────────────────────────
#  SERVICES / SRC (AIX: lssrc / startsrc / stopsrc)
# ───────────────────────────────────────────────

lssrc() {
    # AIX: lssrc -a / lssrc -s sshd   Linux: systemctl status
    case "$1" in
        -a)
            _aix_banner "lssrc -a" "systemctl list-units --type=service"
            systemctl list-units --type=service --no-pager 2>/dev/null || \
                service --status-all 2>/dev/null
            ;;
        -s)
            _aix_banner "lssrc -s $2" "systemctl status $2"
            systemctl status "$2" --no-pager 2>/dev/null || service "$2" status
            ;;
        -g)
            _aix_banner "lssrc -g $2" "systemctl list-units | grep $2"
            systemctl list-units --type=service --no-pager 2>/dev/null | grep -i "$2"
            ;;
        *)
            _aix_banner "lssrc" "systemctl list-units --type=service"
            systemctl list-units --type=service --state=running --no-pager 2>/dev/null
            ;;
    esac
}

startsrc() {
    # AIX: startsrc -s sshd   Linux: systemctl start
    _aix_banner "startsrc -s $2" "sudo systemctl start $2"
    if [[ "$1" == "-s" && -n "$2" ]]; then
        sudo systemctl start "$2" && echo "[OK] Service '$2' started." || \
            sudo service "$2" start
    else
        echo "Usage: startsrc -s <service>"
    fi
}

stopsrc() {
    # AIX: stopsrc -s sshd   Linux: systemctl stop
    _aix_banner "stopsrc -s $2" "sudo systemctl stop $2"
    if [[ "$1" == "-s" && -n "$2" ]]; then
        sudo systemctl stop "$2" && echo "[OK] Service '$2' stopped." || \
            sudo service "$2" stop
    else
        echo "Usage: stopsrc -s <service>"
    fi
}

refresh() {
    # AIX: refresh -s inetd   Linux: systemctl reload
    _aix_banner "refresh -s $2" "sudo systemctl reload $2"
    if [[ "$1" == "-s" && -n "$2" ]]; then
        sudo systemctl reload "$2" 2>/dev/null || \
        sudo systemctl restart "$2" && echo "[OK] Service '$2' refreshed."
    else
        echo "Usage: refresh -s <service>"
    fi
}

lsitab() {
    # AIX: lsitab -a (list /etc/inittab)   Linux: systemctl list-unit-files
    _aix_banner "lsitab -a" "systemctl list-unit-files"
    systemctl list-unit-files --type=service --no-pager 2>/dev/null | less
}

mkitab() {
    # AIX: mkitab "sshd:2:respawn:/usr/sbin/sshd"   Linux: systemctl enable
    _aix_banner "mkitab" "sudo systemctl enable"
    local svc="$1"
    if [[ -z "$svc" ]]; then echo "Usage: mkitab <service>"; return 1; fi
    sudo systemctl enable "$svc" && echo "[OK] Service '$svc' enabled at boot."
}

rmitab() {
    # AIX: rmitab sshd   Linux: systemctl disable
    _aix_banner "rmitab $1" "sudo systemctl disable $1"
    if [[ -z "$1" ]]; then echo "Usage: rmitab <service>"; return 1; fi
    sudo systemctl disable "$1" && echo "[OK] Service '$1' disabled from boot."
}

# ───────────────────────────────────────────────
#  HACMP / PowerHA CLUSTER — Stubs (WSL only)
# ───────────────────────────────────────────────

clstat() {
    _aix_stub "clstat"
    echo "  In AIX: clstat shows PowerHA cluster node status and health."
    echo ""
    printf "  %-20s %-10s %-10s\n" "NODE" "STATE" "ROLE"
    printf "  %-20s %-10s %-10s\n" "$(hostname)" "UP" "PRIMARY"
    printf "  %-20s %-10s %-10s\n" "$(hostname)-node2" "UP" "STANDBY"
}

clRGinfo() {
    _aix_stub "clRGinfo"
    echo "  In AIX: clRGinfo shows which node owns each Resource Group."
    echo ""
    printf "  %-20s %-10s %-20s\n" "RESOURCE GROUP" "STATE" "NODE"
    printf "  %-20s %-10s %-20s\n" "CMOD_RG" "ONLINE" "$(hostname)"
}

clfindres() {
    _aix_stub "clfindres"
    echo "  In AIX: clfindres locates and describes cluster resources."
    echo "  Usage: clfindres -r RESOURCE_GROUP_NAME"
}

oslevel() {
    # AIX: report installed maintenance level of the OS
    # Real AIX: oslevel -s  →  7200-05-03-2148
    case "${1:-}" in
        -s)  echo "7200-05-03-2148" ;;
        -r)  echo "7200-05" ;;
        -g)  printf '7200-05-03-2148\n7200-05-02-2036\n7200-05-01-2009\n' ;;
        -q)  echo "7.2.0.0" ;;
        *)   echo "7.2.0.0" ;;
    esac
}

# ── Live Watches (ported from aix_launch.sh) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

errwatch() {
    # AIX equivalent: continuous errpt monitoring (like 'errpt -a' on a loop)
    # Mirrors the errpt-watch window in aix_launch.sh
    local interval="${1:-10}"
    _aix_banner "errwatch" "live dmesg + journalctl loop (${interval}s refresh)"
    echo -e "\e[33mPress Ctrl-C to stop\e[0m"
    while true; do
        clear
        echo -e "\e[33m$(date '+%Y-%m-%d %H:%M:%S') -- AIX errpt live watch (refreshing every ${interval}s)\e[0m"
        printf '═%.0s' {1..60}; echo
        echo "=== Kernel Errors (dmesg) ==="
        dmesg --level=err,crit 2>/dev/null | tail -10 || \
            dmesg | grep -iE "error|fail" | tail -10
        echo ""
        echo "=== System Journal Errors ==="
        journalctl -p err --no-pager -n 15 2>/dev/null || \
            grep -iE "error|fail|kernel" /var/log/syslog 2>/dev/null | tail -15
        sleep "$interval"
    done
}

clwatch() {
    # AIX: continuous clstat / clRGinfo monitoring (HACMP cluster watch)
    # Mirrors the clstat-watch window in aix_launch.sh
    # Usage: clwatch [interval_seconds]   default: 5s
    local interval="${1:-5}"
    _aix_banner "clwatch" "live clstat + clRGinfo loop (${interval}s refresh)"
    echo -e "\e[33mPress Ctrl-C to stop\e[0m"
    while true; do
        clear
        echo -e "\e[33m$(date '+%Y-%m-%d %H:%M:%S') -- Cluster live watch (refreshing every ${interval}s)\e[0m"
        printf '═%.0s' {1..60}; echo
        echo "=== Cluster Node Status (clstat) ==="
        clstat 2>/dev/null
        echo ""
        echo "=== Resource Groups (clRGinfo) ==="
        clRGinfo 2>/dev/null
        sleep "$interval"
    done
}

# ───────────────────────────────────────────────
#  SMIT / SMITTY — AIX System Management Interface Tool
#  smit   = AIX GUI version (we emulate as whiptail TUI — same on WSL)
#  smitty = AIX text/curses version (forced TUI — identical here)
# ───────────────────────────────────────────────

_smit_check() {
    if ! command -v whiptail &>/dev/null; then
        echo "[INFO] Installing whiptail for SMIT menu interface..."
        sudo apt-get install -y whiptail 2>/dev/null || \
            { echo "[ERROR] Could not install whiptail. Run: sudo apt install whiptail"; return 1; }
    fi
    return 0
}

_smit_pause() {
    echo ""
    read -rp "Press ENTER to return to menu..." _
}

# ── Software Management submenu ──────────────────
_smit_software() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Software Management" \
            --menu "Select an action:" 20 65 10 \
            "1" "List installed packages" \
            "2" "Install a package" \
            "3" "Remove a package" \
            "4" "Search for a package" \
            "5" "Update all packages" \
            "6" "Show package details" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit software → list" "dpkg -l"
               dpkg -l | less; _smit_pause ;;
            2) local pkg
               pkg=$(whiptail --title "Install Package" --inputbox "Package name to install:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit install $pkg" "sudo apt install $pkg"
               sudo apt install -y "$pkg"; _smit_pause ;;
            3) local pkg
               pkg=$(whiptail --title "Remove Package" --inputbox "Package name to remove:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit remove $pkg" "sudo apt remove $pkg"
               sudo apt remove -y "$pkg"; _smit_pause ;;
            4) local pkg
               pkg=$(whiptail --title "Search Package" --inputbox "Search term:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit software search" "apt search $pkg"
               apt search "$pkg" 2>/dev/null | head -40; _smit_pause ;;
            5) clear; _aix_banner "smit update" "sudo apt update && sudo apt upgrade"
               sudo apt update && sudo apt upgrade; _smit_pause ;;
            6) local pkg
               pkg=$(whiptail --title "Package Details" --inputbox "Package name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit software details" "apt show $pkg"
               apt show "$pkg" 2>/dev/null; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Storage / LVM submenu ────────────────────────
_smit_storage() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Storage / LVM Management" \
            --menu "Select an action:" 26 68 16 \
            "1"  "List disks              (lspv → lsblk)" \
            "2"  "List volume groups      (lsvg → vgdisplay)" \
            "3"  "List logical volumes    (lsvg -l → lvdisplay)" \
            "4"  "Disk usage summary      (df -g → df -h)" \
            "5"  "List file systems       (lsfs → mount)" \
            "6"  "Disk I/O stats          (iostat)" \
            "7"  "Create logical volume   (mklv → lvcreate)" \
            "8"  "Remove logical volume   (rmlv → lvremove)" \
            "9"  "Change logical volume   (chlv → lvrename/lvextend)" \
            "10" "Create filesystem       (crfs → mkfs + mount)" \
            "11" "Change filesystem size  (chfs → lvextend + resize2fs)" \
            "12" "Remove filesystem       (rmfs → umount + lvremove)" \
            "b"  "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1)  clear; lspv; _smit_pause ;;
            2)  clear; lsvg; _smit_pause ;;
            3)  clear; lsvg -l; _smit_pause ;;
            4)  clear; df -h; _smit_pause ;;
            5)  clear; lsfs; _smit_pause ;;
            6)  clear; _aix_banner "smit storage iostat" "iostat -xh 2 3"
                command iostat -xh 2 3 2>/dev/null || \
                    echo "[INFO] iostat not found. Run: sudo apt install sysstat"; _smit_pause ;;
            7)  clear; mklv; _smit_pause ;;
            8)  local lv
                lv=$(whiptail --title "Remove LV" --inputbox "Logical volume name:" 8 50 3>&1 1>&2 2>&3) || continue
                clear; rmlv "$lv"; _smit_pause ;;
            9)  clear; chlv; _smit_pause ;;
            10) clear; crfs; _smit_pause ;;
            11) clear; chfs; _smit_pause ;;
            12) local mnt
                mnt=$(whiptail --title "Remove FS" --inputbox "Mount point to remove:" 8 50 3>&1 1>&2 2>&3) || continue
                if whiptail --title "Confirm" --yesno "Remove filesystem at '$mnt'?" 8 50; then
                    clear; rmfs "$mnt"; _smit_pause
                fi ;;
            b)  return ;;
        esac
    done
}

# ── Network submenu ──────────────────────────────
_smit_network() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Network Configuration" \
            --menu "Select an action:" 20 65 12 \
            "1" "Show interfaces (entstat → ip addr)" \
            "2" "Show routing table (netstat -r → ip route)" \
            "3" "Show active connections (netstat → ss -tunp)" \
            "4" "Ping a host" \
            "5" "DNS lookup (nslookup)" \
            "6" "Show network tuning (no -o → sysctl net.*)" \
            "7" "Interface statistics (ip -s link)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit network" "ip addr show"; ip addr show; _smit_pause ;;
            2) clear; _aix_banner "smit routing" "ip route"; ip route; _smit_pause ;;
            3) clear; _aix_banner "smit netstat" "ss -tunp"; ss -tunp; _smit_pause ;;
            4) local host
               host=$(whiptail --title "Ping Host" --inputbox "Hostname or IP:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; ping -c 4 "$host"; _smit_pause ;;
            5) local host
               host=$(whiptail --title "DNS Lookup" --inputbox "Hostname to resolve:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; nslookup "$host" 2>/dev/null || host "$host"; _smit_pause ;;
            6) clear; no -o; _smit_pause ;;
            7) clear; _aix_banner "smit entstat" "ip -s link"; ip -s link; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Users & Groups submenu ───────────────────────
_smit_users() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Users & Groups" \
            --menu "Select an action:" 22 65 12 \
            "1" "List all users (lsuser ALL)" \
            "2" "Add a user (mkuser)" \
            "3" "Change user password (passwd)" \
            "4" "Modify user account (usermod)" \
            "5" "Delete a user (userdel)" \
            "6" "List groups" \
            "7" "Add a group" \
            "8" "UNLOCK a locked user (chuser account_locked=false)" \
            "9" "LOCK a user account  (chuser account_locked=true)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; lsuser; _smit_pause ;;
            2) local usr
               usr=$(whiptail --title "Add User" --inputbox "New username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; mkuser "$usr"; _smit_pause ;;
            3) local usr
               usr=$(whiptail --title "Change Password" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit passwd $usr" "passwd $usr"; passwd "$usr"; _smit_pause ;;
            4) local usr args
               usr=$(whiptail --title "Modify User" --inputbox "Username to modify:" 8 50 3>&1 1>&2 2>&3) || continue
               args=$(whiptail --title "Modify User" --inputbox "usermod arguments (e.g. -aG sudo $usr):" 8 60 "-aG sudo $usr" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit usermod" "sudo usermod $args"
               eval "sudo usermod $args"; _smit_pause ;;
            5) local usr
               usr=$(whiptail --title "Delete User" --inputbox "Username to delete:" 8 50 3>&1 1>&2 2>&3) || continue
               if whiptail --title "Confirm" --yesno "Delete user '$usr'?" 8 40; then
                   clear; _aix_banner "smit rmuser $usr" "sudo userdel $usr"
                   sudo userdel "$usr"; _smit_pause
               fi ;;
            6) clear; _aix_banner "smit groups" "cat /etc/group"
               column -t -s: /etc/group | less; _smit_pause ;;
            7) local grp
               grp=$(whiptail --title "Add Group" --inputbox "New group name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit mkgroup $grp" "sudo groupadd $grp"
               sudo groupadd "$grp" && echo "[OK] Group '$grp' created."; _smit_pause ;;
            8) local usr
               usr=$(whiptail --title "Unlock User" --inputbox "Username to UNLOCK:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; chuser account_locked=false "$usr"; _smit_pause ;;
            9) local usr
               usr=$(whiptail --title "Lock User" --inputbox "Username to LOCK:" 8 50 3>&1 1>&2 2>&3) || continue
               if whiptail --title "Confirm" --yesno "Lock account for '$usr'?" 8 45; then
                   clear; chuser account_locked=true "$usr"; _smit_pause
               fi ;;
            b) return ;;
        esac
    done
}

# ── Performance submenu ──────────────────────────
_smit_perf() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Performance Monitoring" \
            --menu "Select an action:" 20 65 10 \
            "1" "Interactive monitor (nmon)" \
            "2" "CPU & memory overview (svmon -G)" \
            "3" "Process memory (svmon -P <pid>)" \
            "4" "Virtual memory stats (vmstat)" \
            "5" "I/O statistics (iostat)" \
            "6" "Top processes (top)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; nmon ;;
            2) clear; svmon -G; _smit_pause ;;
            3) local pid
               pid=$(whiptail --title "svmon -P" --inputbox "Enter PID:" 8 40 3>&1 1>&2 2>&3) || continue
               clear; svmon -P "$pid"; _smit_pause ;;
            4) clear; _aix_banner "smit vmstat" "vmstat 1 5"; vmstat 1 5; _smit_pause ;;
            5) clear; _aix_banner "smit iostat" "iostat -xh 1 5"
               command iostat -xh 1 5 2>/dev/null || echo "[INFO] Run: sudo apt install sysstat"; _smit_pause ;;
            6) clear; top ;;
            b) return ;;
        esac
    done
}

# ── Error Log submenu ────────────────────────────
_smit_errlog() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Error Logging" \
            --menu "Select an action:" 20 65 8 \
            "1" "All errors (errpt -a)" \
            "2" "Hardware errors (errpt -d H)" \
            "3" "Software errors (errpt -d S)" \
            "4" "Search error log (errpt -j)" \
            "5" "Live kernel messages (dmesg -w)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; errpt -a; _smit_pause ;;
            2) clear; errpt -d H; _smit_pause ;;
            3) clear; errpt -d S; _smit_pause ;;
            4) local term
               term=$(whiptail --title "Error Search" --inputbox "Search term:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; errpt -j "$term"; _smit_pause ;;
            5) clear; _aix_banner "smit errlog live" "dmesg -w"
               echo "(Press Ctrl+C to stop)"; dmesg -w ;;
            b) return ;;
        esac
    done
}

# ── Devices submenu ──────────────────────────────
_smit_devices() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Devices" \
            --menu "Select an action:" 22 68 10 \
            "1" "List all devices        (lsdev)" \
            "2" "List block devices      (lspv → lsblk)" \
            "3" "List PCI devices        (lspci)" \
            "4" "Refresh device config   (cfgmgr → udevadm trigger)" \
            "5" "USB devices             (lsusb)" \
            "6" "Device attributes       (lsattr → udevadm info)" \
            "7" "Change device setting   (chdev → ip link / sysctl)" \
            "8" "Multipath device paths  (lspath → multipath -l)" \
            "9" "Update boot loader      (bosboot → update-grub)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; lsdev; _smit_pause ;;
            2) clear; lspv; _smit_pause ;;
            3) clear; _aix_banner "smit pci" "lspci"
               command lspci 2>/dev/null || echo "[INFO] Run: sudo apt install pciutils"; _smit_pause ;;
            4) clear; cfgmgr; _smit_pause ;;
            5) clear; _aix_banner "smit usb" "lsusb"
               command lsusb 2>/dev/null || echo "[INFO] Run: sudo apt install usbutils"; _smit_pause ;;
            6) local dev
               dev=$(whiptail --title "lsattr" --inputbox "Device name (e.g. hdisk0, sys0):" 8 60 "sys0" 3>&1 1>&2 2>&3) || continue
               clear; lsattr -El "$dev"; _smit_pause ;;
            7) clear; chdev; _smit_pause ;;
            8) clear; lspath; _smit_pause ;;
            9) if whiptail --title "bosboot" --yesno "Update boot loader (bosboot equivalent)?" 8 55; then
                   clear; bosboot; _smit_pause
               fi ;;
            b) return ;;
        esac
    done
}

# ── System Info submenu ──────────────────────────
_smit_system() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ System Information" \
            --menu "Select an action:" 20 65 8 \
            "1" "Hostname & OS info (uname -a)" \
            "2" "System uptime" \
            "3" "CPU info" \
            "4" "Memory info" \
            "5" "Kernel version" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit system" "uname -a"; uname -a; cat /etc/os-release 2>/dev/null; _smit_pause ;;
            2) clear; _aix_banner "smit uptime" "uptime"; uptime; _smit_pause ;;
            3) clear; _aix_banner "smit cpu" "lscpu"; lscpu; _smit_pause ;;
            4) clear; _aix_banner "smit memory" "free -h + /proc/meminfo"; free -h; echo ""; grep -E "MemTotal|MemFree|SwapTotal|SwapFree" /proc/meminfo; _smit_pause ;;
            5) clear; _aix_banner "smit kernel" "uname -r"; uname -r; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── HACMP / Cluster submenu ──────────────────────
_smit_hacmp() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ HACMP / Cluster" \
            --menu "Select an action:" 20 65 8 \
            "1" "Cluster status (clstat)" \
            "2" "Resource group info (clRGinfo)" \
            "3" "Find cluster resource (clfindres)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; clstat; _smit_pause ;;
            2) clear; clRGinfo; _smit_pause ;;
            3) local rg
               rg=$(whiptail --title "clfindres" --inputbox "Resource Group name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; clfindres -r "$rg"; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Services / SRC submenu ──────────────────────
_smit_services() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Services / SRC" \
            --menu "Select an action:" 22 68 12 \
            "1" "List all services       (lssrc -a)" \
            "2" "Status of a service     (lssrc -s <svc>)" \
            "3" "Start a service         (startsrc -s <svc>)" \
            "4" "Stop a service          (stopsrc -s <svc>)" \
            "5" "Reload/Refresh service  (refresh -s <svc>)" \
            "6" "Enable at boot          (mkitab / systemctl enable)" \
            "7" "Disable at boot         (rmitab / systemctl disable)" \
            "8" "List boot-enabled svcs  (lsitab -a)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; lssrc -a | less; _smit_pause ;;
            2) local svc
               svc=$(whiptail --title "Service Status" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; lssrc -s "$svc"; _smit_pause ;;
            3) local svc
               svc=$(whiptail --title "Start Service" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; startsrc -s "$svc"; _smit_pause ;;
            4) local svc
               svc=$(whiptail --title "Stop Service" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               if whiptail --title "Confirm" --yesno "Stop service '$svc'?" 8 45; then
                   clear; stopsrc -s "$svc"; _smit_pause
               fi ;;
            5) local svc
               svc=$(whiptail --title "Refresh Service" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; refresh -s "$svc"; _smit_pause ;;
            6) local svc
               svc=$(whiptail --title "Enable at Boot" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; mkitab "$svc"; _smit_pause ;;
            7) local svc
               svc=$(whiptail --title "Disable at Boot" --inputbox "Service name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; rmitab "$svc"; _smit_pause ;;
            8) clear; lsitab; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Cron / Scheduled Jobs submenu ───────────────
_smit_cron() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Cron / Scheduled Jobs" \
            --menu "Select an action:" 20 65 8 \
            "1" "Edit my crontab         (crontab -e)" \
            "2" "List my crontab         (crontab -l)" \
            "3" "Edit another user's cron (sudo crontab -u)" \
            "4" "List another user's cron (sudo crontab -u -l)" \
            "5" "List system cron jobs    (/etc/cron.d/)" \
            "6" "Schedule a one-time job  (at)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit cron edit" "crontab -e"; crontab -e; _smit_pause ;;
            2) clear; _aix_banner "smit cron list" "crontab -l"
               crontab -l 2>/dev/null || echo "[INFO] No crontab for $USER"; _smit_pause ;;
            3) local usr
               usr=$(whiptail --title "Edit User Crontab" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit crontab $usr" "sudo crontab -u $usr -e"
               sudo crontab -u "$usr" -e; _smit_pause ;;
            4) local usr
               usr=$(whiptail --title "List User Crontab" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit crontab -l $usr" "sudo crontab -u $usr -l"
               sudo crontab -u "$usr" -l 2>/dev/null || echo "[INFO] No crontab for $usr"; _smit_pause ;;
            5) clear; _aix_banner "smit syscron" "ls /etc/cron*"
               echo "=== /etc/cron.d/ ==="; ls -la /etc/cron.d/ 2>/dev/null
               echo ""; echo "=== /etc/cron.daily/ ==="; ls /etc/cron.daily/ 2>/dev/null
               echo ""; echo "=== /etc/cron.weekly/ ==="; ls /etc/cron.weekly/ 2>/dev/null; _smit_pause ;;
            6) local cmd when
               cmd=$(whiptail --title "at - Schedule Job" --inputbox "Command to run:" 8 60 3>&1 1>&2 2>&3) || continue
               when=$(whiptail --title "at - Schedule Job" --inputbox "When? (e.g. now +1 hour, 14:30, tomorrow):" 8 60 "now +1 hour" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit at" "echo cmd | at when"
               echo "$cmd" | at "$when" 2>&1; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── NFS submenu ──────────────────────────────────
_smit_nfs() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ NFS" \
            --menu "Select an action:" 20 65 8 \
            "1" "List NFS exports         (exportfs -v)" \
            "2" "List NFS mounts          (mount -t nfs)" \
            "3" "Show NFS stats           (nfsstat)" \
            "4" "Export a directory       (exportfs)" \
            "5" "Mount an NFS share       (mount -t nfs)" \
            "6" "Unmount an NFS share     (umount)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit nfs exports" "exportfs -v"
               sudo exportfs -v 2>/dev/null || echo "[INFO] nfs-kernel-server not installed. Run: sudo apt install nfs-kernel-server"; _smit_pause ;;
            2) clear; _aix_banner "smit nfs mounts" "mount -t nfs"
               mount -t nfs 2>/dev/null || echo "[INFO] No NFS mounts active."; _smit_pause ;;
            3) clear; _aix_banner "smit nfsstat" "nfsstat"
               nfsstat 2>/dev/null || echo "[INFO] Install nfs-common: sudo apt install nfs-common"; _smit_pause ;;
            4) local dir opts
               dir=$(whiptail --title "Export Directory" --inputbox "Directory to export:" 8 60 "/data" 3>&1 1>&2 2>&3) || continue
               opts=$(whiptail --title "Export Options" --inputbox "Options (e.g. *(rw,sync,no_subtree_check)):" 8 60 "*(ro,sync)" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit mknfsexp" "exportfs + /etc/exports"
               echo "$dir $opts" | sudo tee -a /etc/exports
               sudo exportfs -ra 2>/dev/null && echo "[OK] Export updated."; _smit_pause ;;
            5) local server share mnt
               server=$(whiptail --title "Mount NFS" --inputbox "NFS server hostname/IP:" 8 50 3>&1 1>&2 2>&3) || continue
               share=$(whiptail --title "Mount NFS" --inputbox "Remote share path (e.g. /data):" 8 50 3>&1 1>&2 2>&3) || continue
               mnt=$(whiptail --title "Mount NFS" --inputbox "Local mount point:" 8 50 "/mnt/nfs" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit mknfsmnt" "sudo mount -t nfs"
               sudo mkdir -p "$mnt"
               sudo mount -t nfs "${server}:${share}" "$mnt" && echo "[OK] Mounted ${server}:${share} → $mnt"; _smit_pause ;;
            6) local mnt
               mnt=$(whiptail --title "Unmount NFS" --inputbox "Mount point to unmount:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit rmnfsmnt" "sudo umount $mnt"
               sudo umount "$mnt" && echo "[OK] Unmounted $mnt"; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Paging / Swap submenu ────────────────────────
_smit_paging() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Paging Space (Swap)" \
            --menu "Select an action:" 20 65 8 \
            "1" "List paging spaces       (lspaging)" \
            "2" "Add a paging space       (mkps)" \
            "3" "Remove a paging space    (rmps)" \
            "4" "Swap usage details       (vmstat -s)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; lspaging; _smit_pause ;;
            2) local sz fl
               sz=$(whiptail --title "Add Swap" --inputbox "Size (e.g. 2G):" 8 40 "2G" 3>&1 1>&2 2>&3) || continue
               fl=$(whiptail --title "Add Swap" --inputbox "Swap file path:" 8 50 "/swapfile2" 3>&1 1>&2 2>&3) || continue
               clear; mkps "$sz" "$fl"; _smit_pause ;;
            3) local sw
               sw=$(whiptail --title "Remove Swap" --inputbox "Swap file or device:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; rmps "$sw"; _smit_pause ;;
            4) clear; _aix_banner "smit pgsp vmstat" "vmstat -s | grep swap"
               vmstat -s | grep -i swap; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Backup / Restore submenu ─────────────────────
_smit_backup() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Backup / Restore" \
            --menu "Select an action:" 20 65 10 \
            "1" "Backup directory → tar.gz (mksysb equiv)" \
            "2" "Backup directory → tar.bz2" \
            "3" "Restore from tar archive" \
            "4" "List tar archive contents" \
            "5" "Sync/mirror with rsync" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) local src dst
               src=$(whiptail --title "Backup" --inputbox "Source directory:" 8 60 "/home" 3>&1 1>&2 2>&3) || continue
               dst=$(whiptail --title "Backup" --inputbox "Destination file (.tar.gz):" 8 60 "/tmp/backup_$(date +%Y%m%d).tar.gz" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit mksysb" "tar -czf"
               tar -czf "$dst" "$src" 2>/dev/null && echo "[OK] Backup saved: $dst" || echo "[ERROR] Backup failed."; _smit_pause ;;
            2) local src dst
               src=$(whiptail --title "Backup bz2" --inputbox "Source directory:" 8 60 "/home" 3>&1 1>&2 2>&3) || continue
               dst=$(whiptail --title "Backup bz2" --inputbox "Destination file (.tar.bz2):" 8 60 "/tmp/backup_$(date +%Y%m%d).tar.bz2" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit backup bz2" "tar -cjf"
               tar -cjf "$dst" "$src" 2>/dev/null && echo "[OK] Backup saved: $dst"; _smit_pause ;;
            3) local arc dst
               arc=$(whiptail --title "Restore" --inputbox "Archive file to restore:" 8 60 3>&1 1>&2 2>&3) || continue
               dst=$(whiptail --title "Restore" --inputbox "Restore to directory:" 8 60 "/tmp/restore" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit restore" "tar -xf"
               mkdir -p "$dst" && tar -xf "$arc" -C "$dst" 2>/dev/null && echo "[OK] Restored to $dst"; _smit_pause ;;
            4) local arc
               arc=$(whiptail --title "List Archive" --inputbox "Archive file:" 8 60 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit backup list" "tar -tvf"
               tar -tvf "$arc" 2>/dev/null | less; _smit_pause ;;
            5) local src dst
               src=$(whiptail --title "rsync" --inputbox "Source path:" 8 60 3>&1 1>&2 2>&3) || continue
               dst=$(whiptail --title "rsync" --inputbox "Destination (local or user@host:/path):" 8 60 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit backup rsync" "rsync -avh"
               rsync -avh --progress "$src" "$dst"; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Process Management submenu ───────────────────
_smit_process() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Process Management" \
            --menu "Select an action:" 20 65 10 \
            "1" "List all processes       (ps -ef)" \
            "2" "Find process by name     (pgrep)" \
            "3" "Kill a process by PID    (kill)" \
            "4" "Kill a process by name   (pkill)" \
            "5" "Change process priority  (renice)" \
            "6" "Interactive process view (top)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit ps" "ps -ef"; ps -ef | less; _smit_pause ;;
            2) local nm
               nm=$(whiptail --title "Find Process" --inputbox "Process name:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit pgrep $nm" "pgrep -la $nm"
               pgrep -la "$nm" 2>/dev/null || ps -ef | grep -v grep | grep -i "$nm"; _smit_pause ;;
            3) local pid sig
               pid=$(whiptail --title "Kill Process" --inputbox "PID to kill:" 8 40 3>&1 1>&2 2>&3) || continue
               sig=$(whiptail --title "Kill Signal" --menu "Signal:" 12 40 4 \
                   "15" "SIGTERM (graceful)" "9" "SIGKILL (force)" "1" "SIGHUP (reload)" \
                   3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit kill -$sig $pid" "kill -$sig $pid"
               kill -"$sig" "$pid" && echo "[OK] Signal $sig sent to PID $pid."; _smit_pause ;;
            4) local nm
               nm=$(whiptail --title "Kill by Name" --inputbox "Process name to kill:" 8 50 3>&1 1>&2 2>&3) || continue
               if whiptail --title "Confirm" --yesno "Kill all processes named '$nm'?" 8 50; then
                   clear; _aix_banner "smit pkill $nm" "pkill $nm"
                   pkill "$nm" && echo "[OK] Killed processes matching '$nm'."; _smit_pause
               fi ;;
            5) local pid nice
               pid=$(whiptail --title "Renice" --inputbox "PID:" 8 40 3>&1 1>&2 2>&3) || continue
               nice=$(whiptail --title "Renice" --inputbox "New priority (-20 high to 19 low):" 8 50 "0" 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit renice $nice $pid" "renice -n $nice $pid"
               renice -n "$nice" -p "$pid" && echo "[OK] PID $pid priority set to $nice."; _smit_pause ;;
            6) clear; top ;;
            b) return ;;
        esac
    done
}

# ── Security submenu ─────────────────────────────
_smit_security() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Security" \
            --menu "Select an action:" 22 68 12 \
            "1" "Password policy for user (chage -l)" \
            "2" "Set password expiry      (chuser maxage)" \
            "3" "Set account expiry date  (chuser expires)" \
            "4" "Unlock locked user       (chuser account_locked=false)" \
            "5" "Lock user account        (chuser account_locked=true)" \
            "6" "Show failed login info   (faillock)" \
            "7" "List sudo privileges     (sudo -l)" \
            "8" "Add user to sudo group   (usermod -aG sudo)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) local usr
               usr=$(whiptail --title "Password Policy" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit security chage" "chage -l $usr"
               sudo chage -l "$usr"; _smit_pause ;;
            2) local usr days
               usr=$(whiptail --title "Password Expiry" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               days=$(whiptail --title "Password Expiry" --inputbox "Max password age (days):" 8 50 "90" 3>&1 1>&2 2>&3) || continue
               clear; chuser maxage="$days" "$usr"; _smit_pause ;;
            3) local usr dt
               usr=$(whiptail --title "Account Expiry" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               dt=$(whiptail --title "Account Expiry" --inputbox "Expiry date (YYYY-MM-DD or -1 for never):" 8 55 "-1" 3>&1 1>&2 2>&3) || continue
               clear; chuser expires="$dt" "$usr"; _smit_pause ;;
            4) local usr
               usr=$(whiptail --title "Unlock User" --inputbox "Username to UNLOCK:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; chuser account_locked=false "$usr"; _smit_pause ;;
            5) local usr
               usr=$(whiptail --title "Lock User" --inputbox "Username to LOCK:" 8 50 3>&1 1>&2 2>&3) || continue
               if whiptail --title "Confirm" --yesno "Lock account for '$usr'?" 8 45; then
                   clear; chuser account_locked=true "$usr"; _smit_pause
               fi ;;
            6) local usr
               usr=$(whiptail --title "Failed Logins" --inputbox "Username (blank=all):" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit security faillock" "faillock --user $usr"
               if [[ -z "$usr" ]]; then
                   faillock 2>/dev/null || lastb | head -20
               else
                   faillock --user "$usr" 2>/dev/null || lastb "$usr" | head -20
               fi; _smit_pause ;;
            7) clear; _aix_banner "smit sudo -l" "sudo -l"; sudo -l; _smit_pause ;;
            8) local usr
               usr=$(whiptail --title "Add to sudo" --inputbox "Username:" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit security sudo" "sudo usermod -aG sudo $usr"
               sudo usermod -aG sudo "$usr" && echo "[OK] '$usr' added to sudo group."; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Printing submenu ──────────────────────────────
_smit_print() {
    while true; do
        local choice
        choice=$(whiptail --title "SMIT ▸ Printing" \
            --menu "Select an action:" 20 65 8 \
            "1" "List print queues        (lpstat -a)" \
            "2" "List print jobs          (lpq)" \
            "3" "Print a file             (lpr)" \
            "4" "Cancel a print job       (cancel / lprm)" \
            "5" "Add a printer            (lpadmin)" \
            "b" "<< Back" \
            3>&1 1>&2 2>&3) || return
        case "$choice" in
            1) clear; _aix_banner "smit lsallq" "lpstat -a"
               lpstat -a 2>/dev/null || echo "[INFO] CUPS not installed. Run: sudo apt install cups"; _smit_pause ;;
            2) clear; _aix_banner "smit lpq" "lpq -a"
               lpq -a 2>/dev/null || echo "[INFO] No print jobs or CUPS not installed."; _smit_pause ;;
            3) local pfile pq
               pfile=$(whiptail --title "Print File" --inputbox "File to print:" 8 60 3>&1 1>&2 2>&3) || continue
               pq=$(whiptail --title "Print File" --inputbox "Printer name (blank=default):" 8 50 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit lpr" "lpr"
               if [[ -n "$pq" ]]; then lpr -P "$pq" "$pfile"; else lpr "$pfile"; fi
               echo "[OK] Print job submitted."; _smit_pause ;;
            4) local job
               job=$(whiptail --title "Cancel Job" --inputbox "Job ID to cancel:" 8 40 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit cancel $job" "cancel $job"
               cancel "$job" 2>/dev/null || lprm "$job" 2>/dev/null; _smit_pause ;;
            5) local pname puri
               pname=$(whiptail --title "Add Printer" --inputbox "Printer name:" 8 50 3>&1 1>&2 2>&3) || continue
               puri=$(whiptail --title "Add Printer" --inputbox "Device URI (e.g. socket://ip:9100):" 8 60 3>&1 1>&2 2>&3) || continue
               clear; _aix_banner "smit mkpq" "lpadmin -p"
               sudo lpadmin -p "$pname" -E -v "$puri" && echo "[OK] Printer '$pname' added."; _smit_pause ;;
            b) return ;;
        esac
    done
}

# ── Main SMIT menu ───────────────────────────────
smit() {
    _smit_check || return 1

    # Allow direct jump via argument: smit hacmp / smit storage / smit network etc.
    case "${1,,}" in
        software|install|fileset|lslpp|installp) _smit_software; return ;;
        storage|lvm|disk|lspv|lsvg) _smit_storage; return ;;
        fs|filesystem|lsfs)          _smit_storage; return ;;
        network|tcp|tcpip|entstat)   _smit_network; return ;;
        user|users|mkuser|lsuser)    _smit_users; return ;;
        perf|nmon|svmon)             _smit_perf; return ;;
        errlog|errpt|error)          _smit_errlog; return ;;
        devices|dev|lsdev|cfgmgr)   _smit_devices; return ;;
        system|sys|uname)            _smit_system; return ;;
        hacmp|cluster|cl|powerha)    _smit_hacmp; return ;;
        src|services|lssrc|startsrc) _smit_services; return ;;
        cron|job|at|schedule)        _smit_cron; return ;;
        nfs|export|mount)            _smit_nfs; return ;;
        pgsp|paging|swap)            _smit_paging; return ;;
        backup|restore|mksysb)       _smit_backup; return ;;
        process|proc|kill|ps)        _smit_process; return ;;
        security|sec|chage|passwd)   _smit_security; return ;;
        print|printer|lpr|queue)     _smit_print; return ;;
    esac

    # Top-level main menu loop
    while true; do
        local choice
        choice=$(whiptail --title " SMIT — System Management Interface Tool (AIX Emulator) " \
            --menu "Use arrow keys to navigate, ENTER to select:" 28 70 18 \
            "1"  "Software Management         (smit software)" \
            "2"  "Storage / LVM               (smit storage)" \
            "3"  "Network Configuration       (smit network)" \
            "4"  "Users & Groups              (smit users)" \
            "5"  "Security                    (smit security)" \
            "6"  "Services / SRC              (smit src)" \
            "7"  "Performance Monitoring      (smit perf)" \
            "8"  "Paging Space / Swap         (smit pgsp)" \
            "9"  "Error Logging               (smit errlog)" \
            "10" "Devices                     (smit devices)" \
            "11" "NFS                         (smit nfs)" \
            "12" "Cron / Scheduled Jobs       (smit cron)" \
            "13" "Backup / Restore            (smit backup)" \
            "14" "Process Management          (smit process)" \
            "15" "Printing                    (smit print)" \
            "16" "System Information          (smit system)" \
            "17" "HACMP / Cluster             (smit hacmp)" \
            "q"  "Exit SMIT" \
            3>&1 1>&2 2>&3) || break
        case "$choice" in
            1)  _smit_software ;;
            2)  _smit_storage  ;;
            3)  _smit_network  ;;
            4)  _smit_users    ;;
            5)  _smit_security ;;
            6)  _smit_services ;;
            7)  _smit_perf     ;;
            8)  _smit_paging   ;;
            9)  _smit_errlog   ;;
            10) _smit_devices  ;;
            11) _smit_nfs      ;;
            12) _smit_cron     ;;
            13) _smit_backup   ;;
            14) _smit_process  ;;
            15) _smit_print    ;;
            16) _smit_system   ;;
            17) _smit_hacmp    ;;
            q)  break ;;
        esac
    done
}

# smitty = AIX text/curses forced mode — identical to smit in WSL
smitty() {
    smit "$@"
}

# ───────────────────────────────────────────────
#  SHELL IDENTITY — makes sessions look/feel like real AIX ksh
# ───────────────────────────────────────────────

export SHELL=/bin/ksh
export FPATH=/usr/lib/ksh:/usr/local/lib/ksh
export AIX_VERSION="7200-05-03-2148"
export LOGNAME="${LOGNAME:-hjoseph}"
export TERM="${TERM:-vt100}"

# Prompt: red '# ' for root/AIX_ROLE=root, bold '> ' for users
if [[ "${AIX_ROLE}" == "root" ]] || [[ "$EUID" -eq 0 ]]; then
    PS1='\[\e[1;31m\]aixserver01:\w # \[\e[0m\]'
else
    PS1='\[\e[1m\]aixserver01:\w> \[\e[0m\]'
fi
export PS1

# ───────────────────────────────────────────────
#  LOAD BANNER — IBM AIX MOTD style
# ───────────────────────────────────────────────

echo ""
echo -e "\e[36m*******************************************************************************"
echo    "*                                                                             *"
echo    "*                                                                             *"
echo    "*  IBM AIX Version 7.2                                                       *"
echo    "*  TL: 7200-05-03-2148   SP3   (November 2021)                               *"
echo    "*  Copyright IBM Corporation, 1982, 2021.                                    *"
echo    "*                                                                             *"
echo    "*  System:   aixserver01    (pwrx-prod-01)                                   *"
echo    "*  Model:    IBM,9117-MMC   PowerVM LPAR                                      *"
echo    "*  Serial:   021A3BE                                                         *"
echo    "*                                                                             *"
echo -e "*******************************************************************************\e[0m"
echo ""
echo -e "\e[33m  YOU HAVE NEW MAIL.\e[0m"
echo ""
echo -e "\e[36m  smit  |  smitty  |  errwatch [secs]  |  clwatch [secs]  |  oslevel -s\e[0m"
echo ""
