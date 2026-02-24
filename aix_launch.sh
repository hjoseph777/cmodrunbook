#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  aix_launch.sh — AIX Emulator 6-Session Startup Launcher
#  Author: AIX SRE Harry Joseph
#
#  USAGE:
#    chmod +x ~/aix_launch.sh
#    ./aix_launch.sh               # launch all 6 sessions
#
#  TO AUTO-START ON WSL OPEN (add to ~/.bashrc):
#    [[ -z "$TMUX" ]] && bash ~/aix_launch.sh
#
#  REQUIRES:  tmux   (sudo apt install tmux)
#  OPTIONAL:  nmon   (sudo apt install nmon)
#             whiptail already included in most Ubuntu/Debian WSL images
# ═══════════════════════════════════════════════════════════════════

# ── Config ──────────────────────────────────────────────────────────
SESSION="aix"
EMU="/mnt/c/Users/Owner/LearningAIX/aix_emu.sh"   # Path to your AIX emulator script
HACMP=false                      # Set to true if supporting HACMP/cluster

# ── Colour helpers ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
_ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
_error() { echo -e "${RED}[ERR ]${NC}  $*"; }

# ── Pre-flight checks ────────────────────────────────────────────────
preflight() {
    local ok=true

    if ! command -v tmux &>/dev/null; then
        _error "tmux not found. Install it:  sudo apt install tmux"
        ok=false
    fi

    if [[ ! -f "$EMU" ]]; then
        _warn "aix_emu.sh not found at: $EMU"
        _warn "Sessions will open without AIX emulator loaded."
        _warn "Update the EMU variable at the top of this script."
    fi

    if ! command -v nmon &>/dev/null; then
        _warn "nmon not installed — Tab 1 will fall back to htop/top."
        _warn "For full AIX nmon experience:  sudo apt install nmon"
    fi

    if ! command -v whiptail &>/dev/null; then
        _warn "whiptail not found — smit/smitty TUI menus won't work."
        _warn "Fix:  sudo apt install whiptail"
    fi

    [[ "$ok" == true ]] || exit 1
}

# ── Shared: load emulator + print a hint, then leave at prompt ───────
# Each window sources the emulator and shows a one-line tip, then stops.
# The user types commands manually — nothing auto-runs.
_open_window() {
    local name="$1"
    local hint="$2"
    local extra="${3:-}"          # optional extra command (e.g. sudo -v)
    local init="source $EMU 2>/dev/null; clear"
    [[ -n "$extra" ]] && init="$init; $extra"
    init="$init; echo -e '\e[33m  Hint: $hint\e[0m'; echo"
    tmux new-window -t "$SESSION" -n "$name" \; \
        send-keys "$init" Enter
}

# ── Build session ────────────────────────────────────────────────────
build_session() {
    # Kill any existing session with the same name
    tmux kill-session -t "$SESSION" 2>/dev/null

    # ── Window 1: nmon  ───────────────────────────────────────────────
    # Opens a clean shell — type 'nmon' to start the performance GUI
    tmux new-session -d -s "$SESSION" -n "nmon" \; \
        send-keys "source $EMU 2>/dev/null; clear; echo -e '\e[33m  Hint: type nmon to start the performance dashboard\e[0m'; echo" Enter

    # ── Window 2: errpt  ──────────────────────────────────────────────
    _open_window "errpt"   "type  errpt -a  or  errwatch 10  for live error stream"

    # ── Window 3: smit  ───────────────────────────────────────────────
    _open_window "smit"    "type  smit  or  smitty  to launch the admin TUI menu"

    # ── Window 4: ksh  ────────────────────────────────────────────────
    _open_window "ksh"     "general AIX work shell -- all emulator commands available"

    # ── Window 5: root  ───────────────────────────────────────────────
    _open_window "root"    "privileged shell -- type  sudo -i  for root" "sudo -v 2>/dev/null"

    # ── Window 6: clstat  ─────────────────────────────────────────────
    if [[ "$HACMP" == true ]]; then
        _open_window "clstat" "type  clwatch 5  for live cluster status (5s refresh)"
    else
        _open_window "clstat" "type  clstat / clRGinfo / clfindres  (stubs) -- set HACMP=true to activate watch"
    fi

    # Focus back on Tab 1 (nmon)
    tmux select-window -t "$SESSION:nmon"
}

# ── Windows Terminal launcher (Option A) ────────────────────────────
# Uses wt.exe to open all 6 AIX profiles as real WT tabs.
# Requires the profiles from wt_profiles.json to be installed first.
launch_wt() {
    if ! command -v wt.exe &>/dev/null; then
        _warn "wt.exe not found in PATH -- falling back to tmux"
        return 1
    fi

    _info "Opening 6 Windows Terminal tabs..."
    # Open all 6 profiles in the current WT window (-w 0)
    # Each ; separated new-tab becomes its own coloured tab
    wt.exe -w 0 \
        new-tab --profile "AIX: nmon" \; \
        new-tab --profile "AIX: errpt" \; \
        new-tab --profile "AIX: smit" \; \
        new-tab --profile "AIX: ksh" \; \
        new-tab --profile "AIX: root" \; \
        new-tab --profile "AIX: clstat" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        _ok "All 6 AIX tabs opened in Windows Terminal."
        _info "If profiles are missing, install them from: wt_profiles.json"
        return 0
    else
        _warn "wt.exe reported an error -- check profiles are installed"
        _warn "Install profiles from: wt_profiles.json then retry"
        return 1
    fi
}

# ── Attach or switch (tmux fallback) ────────────────────────────────
attach_session() {
    if [[ -n "$TMUX" ]]; then
        # Already inside tmux — switch instead of nesting
        tmux switch-client -t "$SESSION"
    else
        tmux attach-session -t "$SESSION"
    fi
}

# ── Startup banner ───────────────────────────────────────────────────
print_banner() {
    echo -e "\e[32m"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         🚀  AIX Emulator — 6-Session Launcher               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  Tab 1  %-51s║\n" "nmon          -- performance dashboard"
    printf "║  Tab 2  %-51s║\n" "errpt watch   -- live error stream (10s refresh)"
    printf "║  Tab 3  %-51s║\n" "smit/smitty   -- admin TUI menus"
    printf "║  Tab 4  %-51s║\n" "ksh shell     -- general AIX work"
    printf "║  Tab 5  %-51s║\n" "root shell    -- privileged ops"
    if [[ "$HACMP" == true ]]; then
        printf "║  Tab 6  %-51s║\n" "clstat watch  -- live cluster status (5s refresh)"
    else
        printf "║  Tab 6  %-51s║\n" "clstat stub   -- set HACMP=true to activate"
    fi
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  TMUX shortcuts:                                             ║"
    echo "║    Ctrl-b  [0-5]   → jump to tab by number                  ║"
    echo "║    Ctrl-b  n / p   → next / previous tab                    ║"
    echo "║    Ctrl-b  d       → detach (sessions stay running)         ║"
    echo "║    Ctrl-b  &       → kill current window                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "\e[0m"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    print_banner
    preflight

    # Detect Windows Terminal ($WT_SESSION is set by WT automatically)
    if [[ -n "$WT_SESSION" ]]; then
        _info "Windows Terminal detected -- launching 6 WT profiles..."
        if launch_wt; then
            exit 0
        fi
        _warn "Falling back to tmux mode..."
    else
        _info "Not in Windows Terminal -- using tmux session"
    fi

    # Fallback: tmux
    _info "Building tmux session: $SESSION ..."
    build_session
    _ok "All 6 windows created. Attaching..."
    sleep 0.5
    attach_session
}

main
