#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  cmod_shift_report.sh — CMOD SRE Shift Health Check Report
#  Author: AIX SRE Harry Joseph
#
#  USAGE:
#    ./cmod_shift_report.sh --start          # Run shift start checks
#    ./cmod_shift_report.sh --end            # Run shift end checks
#    ./cmod_shift_report.sh --watch [secs]   # Live monitor loop
#    ./cmod_shift_report.sh --help           # Show usage
#
#  OUTPUT:
#    Terminal: colour-coded results (RED=critical YELLOW=warning GREEN=ok)
#    Log file: /tmp/cmod_shift_YYYYMMDD_HH_start|end.log
#
#  NOTE: In WSL/lab mode, arsadmin commands are simulated with
#        realistic output. Replace _arsadmin() with real arsadmin
#        binary calls when running on an actual CMOD server.
# ═══════════════════════════════════════════════════════════════════

# ── Config ──────────────────────────────────────────────────────────
CMOD_HOST="${CMOD_HOST:-localhost}"
CMOD_USER="${CMOD_USER:-arsadmin}"
LOG_DIR="${LOG_DIR:-/tmp}"
TIMESTAMP=$(date '+%Y%m%d_%H%M')
DATESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# ── DEMO MODE: Storage Pool Full simulation ───────────────────────────
# Set DEMO_STORAGE_FULL=1 to simulate a Severity 1 ARCHIVE_POOL full alert.
# This is intentional for interview demos to show proactive CMOD monitoring.
# In production: remove this flag and connect to real arsadmin.
DEMO_STORAGE_FULL="${DEMO_STORAGE_FULL:-1}"

# Thresholds
STORAGE_WARN=80    # % pool usage — warning
STORAGE_CRIT=90    # % pool usage — critical
INDEX_WARN=85      # % index usage — warning
SESSION_MAX=50     # max concurrent sessions before alert

# ── Colour helpers ───────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
CYAN='\033[0;36m';   BOLD='\033[1m';       NC='\033[0m'
_ok()    { echo -e "${GREEN}  [  OK  ]${NC}  $*"; }
_warn()  { echo -e "${YELLOW}  [ WARN ]${NC}  $*"; }
_crit()  { echo -e "${RED}  [ CRIT ]${NC}  $*"; }
_info()  { echo -e "${CYAN}  [ INFO ]${NC}  $*"; }
_hdr()   { echo -e "\n${BOLD}${CYAN}$*${NC}"; echo "$(echo "$*" | sed 's/./-/g')"; }

# ── Simulated arsadmin (WSL/Lab mode) ────────────────────────────────
# In production: replace each block with real arsadmin commands
_arsadmin_server_status() {
    # Real: arsadmin query -h $CMOD_HOST
    echo "SERVER_STATUS=UP"
    echo "SERVER_VERSION=9.0.0.5"
    echo "DB2_CONNECTION=OK"
    echo "UPTIME=12d 4h 33m"
}

_arsadmin_storage_pools() {
    # Real: arsadmin qpool -h $CMOD_HOST
    # DEMO: ARCHIVE_POOL is set to 95% to simulate a Severity 1 Storage Full event.
    #       This triggers the STORAGE_CRIT threshold (90%+) so the script turns RED.
    #       Resolution path to explain in interview:
    #         1. Detect:  Script catches PCT >= STORAGE_CRIT and fires _crit()
    #         2. Diagnose: arsload failed because it couldn't write to ARCHIVE_POOL
    #         3. Resolve:  Option A - run: arsadmin expire to free expired documents
    #                      Option B - use: chfs -a size=+5G /cmod/archive  (extend on-the-fly)
    #         4. Verify:   Re-run this script to confirm pool drops below 90%
    if [[ "${DEMO_STORAGE_FULL}" == "1" ]]; then
        echo "POOL_NAME=CACHE_POOL    USED=45   TOTAL=100  PCT=45"
        echo "POOL_NAME=PRIMARY_POOL  USED=72   TOTAL=100  PCT=72"
        echo "POOL_NAME=ARCHIVE_POOL  USED=95   TOTAL=100  PCT=95"  # ← DEMO: SEV1 condition
    else
        echo "POOL_NAME=CACHE_POOL    USED=45   TOTAL=100  PCT=45"
        echo "POOL_NAME=PRIMARY_POOL  USED=72   TOTAL=100  PCT=72"
        echo "POOL_NAME=ARCHIVE_POOL  USED=88   TOTAL=100  PCT=88"
    fi
}

_arsadmin_load_jobs() {
    # Real: arsadmin qload -h $CMOD_HOST -date today
    echo "LOADJOB=RPT_DAILY_STMT   STATUS=COMPLETED  DOCS=14823  TIME=02:14:05"
    echo "LOADJOB=RPT_GL_SUMMARY   STATUS=COMPLETED  DOCS=3401   TIME=01:22:17"
    echo "LOADJOB=RPT_AUDIT_TRAIL  STATUS=FAILED     DOCS=0      TIME=03:01:02  ERROR=ARS0004E"
    echo "LOADJOB=RPT_BRANCH_RPT   STATUS=COMPLETED  DOCS=982    TIME=00:45:11"
    echo "LOADJOB=RPT_EOD_BATCH    STATUS=COMPLETED  DOCS=55234  TIME=04:10:55"
}

_arsadmin_index_status() {
    # Real: arsadmin qindex -h $CMOD_HOST
    echo "INDEX_NAME=STMT_IDX     USED=62  TOTAL=100  PCT=62  STATUS=OK"
    echo "INDEX_NAME=GL_IDX       USED=87  TOTAL=100  PCT=87  STATUS=WARNING"
    echo "INDEX_NAME=AUDIT_IDX    USED=41  TOTAL=100  PCT=41  STATUS=OK"
    echo "INDEX_NAME=BRANCH_IDX   USED=55  TOTAL=100  PCT=55  STATUS=OK"
}

_arsadmin_sessions() {
    # Real: arsadmin qsession -h $CMOD_HOST
    echo "ACTIVE_SESSIONS=12"
    echo "PEAK_TODAY=28"
    echo "STALE_SESSIONS=0"
}

_arsadmin_recent_errors() {
    # Real: tail -100 /var/cmod/log/arssockd.log | grep -iE "error|warn|fail"
    echo "2026-02-22 03:01:02 ARS0004E arsload: Source file not found: /cmod/input/RPT_AUDIT_TRAIL.AFP"
    echo "2026-02-22 01:15:44 ARS1010W Storage pool ARCHIVE_POOL usage exceeds 85%"
    echo "2026-02-22 00:44:11 ARS1001W Slow query detected on BRANCH_IDX (4.2s)"
}

# ── Report state tracking ─────────────────────────────────────────────
ISSUES_CRIT=0
ISSUES_WARN=0
REPORT_LINES=()

_record() { REPORT_LINES+=("$1"); }

# ── Check functions ───────────────────────────────────────────────────

check_server() {
    _hdr "1. CMOD SERVER STATUS"
    local output
    output=$(_arsadmin_server_status)

    local status version db2 uptime
    status=$(echo "$output" | grep SERVER_STATUS | cut -d= -f2)
    version=$(echo "$output" | grep SERVER_VERSION | cut -d= -f2)
    db2=$(echo "$output"    | grep DB2_CONNECTION | cut -d= -f2)
    uptime=$(echo "$output"  | grep UPTIME | cut -d= -f2)

    if [[ "$status" == "UP" ]]; then
        _ok "CMOD Server: UP  (version $version, uptime $uptime)"
        _record "SERVER: OK - v$version up $uptime"
    else
        _crit "CMOD Server: DOWN — escalate immediately"
        _record "SERVER: CRITICAL - SERVER DOWN"
        (( ISSUES_CRIT++ ))
    fi

    if [[ "$db2" == "OK" ]]; then
        _ok "DB2 Connection: OK"
        _record "DB2: OK"
    else
        _crit "DB2 Connection: FAILED — check DB2 instance"
        _record "DB2: CRITICAL - connection failed"
        (( ISSUES_CRIT++ ))
    fi
}

check_storage() {
    _hdr "2. STORAGE POOLS"
    while IFS= read -r line; do
        local pool pct
        pool=$(echo "$line" | awk '{print $1}' | cut -d= -f2)
        pct=$(echo  "$line" | awk '{print $4}' | cut -d= -f2)

        if   (( pct >= STORAGE_CRIT )); then
            _crit "Pool $pool: ${pct}% used — CRITICAL, run migrate/expire now"
            _record "STORAGE $pool: CRITICAL ${pct}%"
            (( ISSUES_CRIT++ ))
        elif (( pct >= STORAGE_WARN )); then
            _warn "Pool $pool: ${pct}% used — WARNING, plan migration"
            _record "STORAGE $pool: WARNING ${pct}%"
            (( ISSUES_WARN++ ))
        else
            _ok  "Pool $pool: ${pct}% used"
            _record "STORAGE $pool: OK ${pct}%"
        fi
    done < <(_arsadmin_storage_pools)
}

check_load_jobs() {
    _hdr "3. LOAD JOBS (TODAY)"
    local fails=0 completed=0
    while IFS= read -r line; do
        local job status error
        job=$(   echo "$line" | awk '{print $1}' | cut -d= -f2)
        status=$(echo "$line" | awk '{print $2}' | cut -d= -f2)
        error=$( echo "$line" | grep -o 'ERROR=[^ ]*' | cut -d= -f2)

        if [[ "$status" == "COMPLETED" ]]; then
            _ok "Load job $job: COMPLETED"
            _record "LOADJOB $job: COMPLETED"
            (( completed++ ))
        else
            _crit "Load job $job: FAILED ($error) — resubmit required"
            _record "LOADJOB $job: FAILED $error"
            (( ISSUES_CRIT++ ))
            (( fails++ ))
        fi
    done < <(_arsadmin_load_jobs)
    echo ""
    _info "Summary: $completed completed, $fails failed"
}

check_index() {
    _hdr "4. INDEX TABLESPACE HEALTH"
    while IFS= read -r line; do
        local idx pct
        idx=$(echo "$line" | awk '{print $1}' | cut -d= -f2)
        pct=$(echo "$line" | awk '{print $3}' | cut -d= -f2)

        if   (( pct >= INDEX_WARN )); then
            _warn "Index $idx: ${pct}% used — run: arsadmin index -clean"
            _record "INDEX $idx: WARNING ${pct}%"
            (( ISSUES_WARN++ ))
        else
            _ok "Index $idx: ${pct}% used"
            _record "INDEX $idx: OK ${pct}%"
        fi
    done < <(_arsadmin_index_status)
}

check_sessions() {
    _hdr "5. USER SESSIONS"
    local output active peak stale
    output=$(_arsadmin_sessions)
    active=$(echo "$output" | grep ACTIVE  | cut -d= -f2)
    peak=$(  echo "$output" | grep PEAK    | cut -d= -f2)
    stale=$( echo "$output" | grep STALE   | cut -d= -f2)

    if (( active >= SESSION_MAX )); then
        _warn "Active sessions: $active (peak today: $peak) — near limit $SESSION_MAX"
        _record "SESSIONS: WARNING $active active"
        (( ISSUES_WARN++ ))
    else
        _ok "Active sessions: $active (peak today: $peak)"
        _record "SESSIONS: OK $active active"
    fi

    if (( stale > 0 )); then
        _warn "Stale sessions: $stale — run: arsadmin endsession -sessionid <id>"
        (( ISSUES_WARN++ ))
    fi
}

check_errors() {
    _hdr "6. RECENT ERROR LOG"
    local errors
    errors=$(_arsadmin_recent_errors)
    if [[ -z "$errors" ]]; then
        _ok "No errors found in recent log"
        _record "ERRORLOG: CLEAN"
    else
        echo "$errors" | while IFS= read -r line; do
            if echo "$line" | grep -q "E "; then
                _crit "$line"
            else
                _warn "$line"
            fi
        done
        _record "ERRORLOG: ERRORS FOUND - review log"
        (( ISSUES_WARN++ ))
    fi
}

check_cpu_headroom() {
    _hdr "7. CPU HEADROOM (User / Wait / Idle)"
    # Uses vmstat: columns us=user, sy=system, wa=wait(I/O), id=idle
    # Format: vmstat 1 3  → take the 3rd sample (skip header + first blip)
    local vmstat_line
    vmstat_line=$(vmstat 1 3 2>/dev/null | tail -1)

    local us sy wa id
    us=$(echo "$vmstat_line" | awk '{print $13}' 2>/dev/null)   # user%
    sy=$(echo "$vmstat_line" | awk '{print $14}' 2>/dev/null)   # system%
    wa=$(echo "$vmstat_line" | awk '{print $16}' 2>/dev/null)   # wait(I/O)%
    id=$(echo "$vmstat_line" | awk '{print $15}' 2>/dev/null)   # idle%

    # Fallback if vmstat column layout differs
    if [[ -z "$id" || "$id" == "0" && "$us" == "0" ]]; then
        _info "CPU Headroom: vmstat output format not matched — skipping"
        _record "CPU: HEADROOM CHECK SKIPPED"
        return
    fi

    _info "CPU snapshot — User: ${us}%  System: ${sy}%  Wait(I/O): ${wa}%  Idle: ${id}%"

    # ── Idle (Headroom) check ─────────────────────────────────────────
    # Triage model:
    #   High User/Sys + Low Idle        → CPU is the bottleneck
    #   Low User/Sys + High Wait        → Disk/I/O is the bottleneck (CPU stuck waiting)
    #   High Idle (>20%)                → System healthy, headroom available
    #   High Idle but user reports slow → pivot to network / DB locking (NOT CPU)

    if (( id < 10 )); then
        _warn  "CPU Idle: ${id}% — system under HEAVY LOAD. Check top / nmon immediately."
        _record "CPU IDLE: WARNING ${id}% — heavy load"
        (( ISSUES_WARN++ ))
    else
        _ok "CPU Idle: ${id}% — adequate headroom"
        _record "CPU IDLE: OK ${id}%"
    fi

    # ── Wait (I/O bottleneck) check ───────────────────────────────────
    if (( wa > 20 )); then
        _crit  "CPU Wait: ${wa}% — STORAGE BOTTLENECK detected. Check iostat / lspv / storage pools."
        _record "CPU WAIT: CRITICAL ${wa}% — I/O bottleneck"
        (( ISSUES_CRIT++ ))
    elif (( wa > 10 )); then
        _warn  "CPU Wait: ${wa}% — elevated I/O wait. Monitor disk activity with iostat."
        _record "CPU WAIT: WARNING ${wa}%"
        (( ISSUES_WARN++ ))
    else
        _ok "CPU Wait: ${wa}% — I/O healthy"
        _record "CPU WAIT: OK ${wa}%"
    fi

    # ── False-alarm guardrail ─────────────────────────────────────────
    if (( id > 20 && wa < 10 )); then
        _info "Headroom OK: If users report slowness, pivot to network or DB locking — NOT CPU."
    fi
}

# ── Summary banner ────────────────────────────────────────────────────
print_summary() {
    local mode="$1"
    local logfile="$2"
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  CMOD SHIFT ${mode^^} REPORT — $DATESTAMP${NC}"
    echo -e "${BOLD}  Host: $HOSTNAME | CMOD: $CMOD_HOST${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    for line in "${REPORT_LINES[@]}"; do
        echo "  $line"
    done
    echo ""
    if   (( ISSUES_CRIT > 0 )); then
        echo -e "${RED}${BOLD}  RESULT: ❌ $ISSUES_CRIT CRITICAL  $ISSUES_WARN WARNING — ACTION REQUIRED${NC}"
    elif (( ISSUES_WARN > 0 )); then
        echo -e "${YELLOW}${BOLD}  RESULT: ⚠️  $ISSUES_WARN WARNING(S) — Monitor closely${NC}"
    else
        echo -e "${GREEN}${BOLD}  RESULT: ✅ ALL CHECKS PASSED — System healthy${NC}"
    fi
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    _info "Log saved to: $logfile"
}

# ── Shift start ───────────────────────────────────────────────────────
run_start() {
    local logfile="$LOG_DIR/cmod_shift_${TIMESTAMP}_start.log"
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       CMOD SHIFT START HEALTH CHECK                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    check_server
    check_storage
    check_load_jobs
    check_index
    check_sessions
    check_errors
    check_cpu_headroom
    print_summary "START" "$logfile"
    {
        echo "CMOD SHIFT START REPORT - $DATESTAMP"
        echo "Host: $HOSTNAME | CMOD: $CMOD_HOST"
        for line in "${REPORT_LINES[@]}"; do echo "$line"; done
        echo "CRITICAL: $ISSUES_CRIT  WARNING: $ISSUES_WARN"
    } > "$logfile"
}

# ── Shift end ─────────────────────────────────────────────────────────
run_end() {
    local logfile="$LOG_DIR/cmod_shift_${TIMESTAMP}_end.log"
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       CMOD SHIFT END   HEALTH CHECK                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    check_server
    check_storage
    check_load_jobs
    check_index
    check_sessions
    check_errors
    check_cpu_headroom
    print_summary "END" "$logfile"
    {
        echo "CMOD SHIFT END REPORT - $DATESTAMP"
        echo "Host: $HOSTNAME | CMOD: $CMOD_HOST"
        for line in "${REPORT_LINES[@]}"; do echo "$line"; done
        echo "CRITICAL: $ISSUES_CRIT  WARNING: $ISSUES_WARN"
    } > "$logfile"
}

# ── Live watch loop ───────────────────────────────────────────────────
run_watch() {
    local interval="${1:-60}"
    _info "CMOD live watch — refreshing every ${interval}s. Ctrl-C to stop."
    while true; do
        clear
        ISSUES_CRIT=0; ISSUES_WARN=0; REPORT_LINES=()
        echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') -- CMOD Live Monitor (${interval}s refresh)${NC}"
        check_server
        check_storage
        check_load_jobs
        sleep "$interval"
    done
}

# ── Help ──────────────────────────────────────────────────────────────
show_help() {
    echo ""
    echo "Usage: $0 [--start | --end | --watch [secs] | --help]"
    echo ""
    echo "  --start         Run shift start health check"
    echo "  --end           Run shift end health check"
    echo "  --watch [secs]  Live monitor loop (default: 60s refresh)"
    echo "  --help          Show this help"
    echo ""
    echo "Environment variables:"
    echo "  CMOD_HOST   CMOD server hostname  (default: localhost)"
    echo "  CMOD_USER   CMOD admin user        (default: arsadmin)"
    echo "  LOG_DIR     Log output directory   (default: /tmp)"
    echo ""
    echo "Examples:"
    echo "  ./cmod_shift_report.sh --start"
    echo "  ./cmod_shift_report.sh --end"
    echo "  ./cmod_shift_report.sh --watch 30"
    echo "  CMOD_HOST=cmodprod1 ./cmod_shift_report.sh --start"
}

# ── Main entry ────────────────────────────────────────────────────────
case "${1:-}" in
    --start)        run_start ;;
    --end)          run_end ;;
    --watch)        run_watch "${2:-60}" ;;
    --help|-h|"")   show_help ;;
    *)              echo "Unknown option: $1"; show_help; exit 1 ;;
esac
