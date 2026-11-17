#!/bin/bash
# SPDX-License-Identifier: MIT
# guest/layer/usr/lib/harborplay/mem-trim (harborplay.mem_trim= on the kernel command line) and its units:
#   default  no option: writes exactly "1" (clean page cache only) to drop_caches
#   off      harborplay.mem_trim=0: drop_caches is not touched
#   other    another value (harborplay.mem_trim=1) behaves like the default
#   game     a game's app-steam-app*.scope under the user manager: drop_caches is not touched, exit 75
#   retry    the service runs the script again after exit 75 instead of never trimming
#   units    the timer is enabled (timers.target.wants), fires once per boot after boot settles,
#            and starts the oneshot service that runs the script
# usage: scripts/test/mem-trim.sh
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)/guest/layer
S=$R/usr/lib/harborplay/mem-trim
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0; fail() { fails=$((fails + 1)); echo "FAIL [$1]: $2"; }
printf 'MemTotal: 8108884 kB\nMemFree: 1000 kB\n' > "$T/meminfo"

mkdir -p "$T/cgroup/user-1000.slice/user@1000.service/app.slice"
run() { # cmdline
    printf '%s\n' "$1" > "$T/cmdline"; rm -f "$T/drop"
    HARBORPLAY_CMDLINE=$T/cmdline HARBORPLAY_DROP_CACHES=$T/drop HARBORPLAY_MEMINFO=$T/meminfo HARBORPLAY_CGROUP=$T/cgroup bash "$S" > "$T/out" 2>&1
}

run "console=hvc0 rootwait" || fail default "exit status $?"
[ "$(cat "$T/drop" 2>/dev/null)" = 1 ] || fail default "drop_caches got '$(cat "$T/drop" 2>/dev/null)', want 1"

run "console=hvc0 harborplay.mem_trim=0 rootwait" || fail off "exit status $?"
[ -e "$T/drop" ] && fail off "drop_caches written although harborplay.mem_trim=0"

run "harborplay.mem_trim=1" || fail other "exit status $?"
[ "$(cat "$T/drop" 2>/dev/null)" = 1 ] || fail other "drop_caches not written"

G=$T/cgroup/user-1000.slice/user@1000.service/app.slice/app-steam-app70-1234.scope
mkdir -p "$G"
run "console=hvc0"; rc=$?
[ $rc = 75 ] || fail game "exit status $rc, want 75"
[ -e "$T/drop" ] && fail game "drop_caches written while a game runs"
rmdir "$G"

U=$R/usr/lib/systemd/system
[ "$(readlink "$U/timers.target.wants/harborplay-mem-trim.timer")" = ../harborplay-mem-trim.timer ] || fail units "timer not enabled"
grep -qx 'OnBootSec=150s' "$U/harborplay-mem-trim.timer" || fail units "timer is not a one-shot after boot"
grep -q '^OnUnitActiveSec\|^OnCalendar' "$U/harborplay-mem-trim.timer" && fail units "timer repeats (must run once per boot)"
grep -qx 'Type=oneshot' "$U/harborplay-mem-trim.service" && grep -qx 'ExecStart=/usr/lib/harborplay/mem-trim' "$U/harborplay-mem-trim.service" \
    || fail units "service does not run the script once"
grep -qx 'RestartForceExitStatus=75' "$U/harborplay-mem-trim.service" && ! grep -q '^SuccessExitStatus=.*75' "$U/harborplay-mem-trim.service" \
    && grep -q '^RestartSec=' "$U/harborplay-mem-trim.service" || fail retry "service does not run again after exit 75"
[ -x "$S" ] && bash -n "$S" || fail units "script not executable or invalid"

[ $fails -eq 0 ] && echo "mem-trim: all PASS" || { echo "mem-trim: $fails FAIL"; exit 1; }
