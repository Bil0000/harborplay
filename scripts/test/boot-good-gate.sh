#!/bin/bash
# SPDX-License-Identifier: MIT
# guest/layer/usr/lib/harborplay/boot-good-gate (steamos-boot.service drop-in):
#   same     the last good build boots again: no wait
#   first    no stamp yet: no wait
#   noport   new build, launcher without harbor.progress: no wait
#   timeout  new build, only an older boot's ready marker: fails, the slot is not marked good
#   ready    new build, this boot's ready marker: succeeds
#   stamp    --stamp records the booted build
#   unit     the drop-in runs it as ExecStartPre (failure stops the stock mark-good command)
# usage: scripts/test/boot-good-gate.sh
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
S=$R/guest/layer/usr/lib/harborplay/boot-good-gate
U=$R/guest/layer/usr/lib/systemd/system/steamos-boot.service.d/50-harborplay.conf
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0; fail() { fails=$((fails + 1)); echo "FAIL [$1]: $2"; }
mkdir -p "$T/etc" "$T/proc/sys/kernel/random" "$T/tmp" "$T/var/lib/harborplay" "$T/dev/virtio-ports"
echo BUILD_ID=20261020.1 > "$T/etc/os-release"
echo boot-1 > "$T/proc/sys/kernel/random/boot_id"
: > "$T/dev/virtio-ports/harbor.progress"
gate() { HARBORPLAY_ROOT=$T HARBORPLAY_READY_TIMEOUT=2 bash "$S" "$@" >/dev/null 2>&1; }

echo 20261020.1 > "$T/var/lib/harborplay/good-build"
gate || fail same "exit $?"
rm "$T/var/lib/harborplay/good-build"
gate || fail first "exit $?"
echo 20260922.6101926 > "$T/var/lib/harborplay/good-build"
rm "$T/dev/virtio-ports/harbor.progress"
gate || fail noport "exit $?"
: > "$T/dev/virtio-ports/harbor.progress"
echo boot-0 > "$T/tmp/.harbor-progress-ready-1000"
gate && fail timeout "marked good without this boot's ready marker"
echo boot-1 > "$T/tmp/.harbor-progress-ready-1000"
gate || fail ready "exit $?"
gate --stamp && [ "$(cat "$T/var/lib/harborplay/good-build")" = 20261020.1 ] || fail stamp "$(cat "$T/var/lib/harborplay/good-build")"
grep -qx 'ExecStartPre=/usr/lib/harborplay/boot-good-gate' "$U" \
    && grep -qx 'ExecStartPost=-/usr/lib/harborplay/boot-good-gate --stamp' "$U" || fail unit "drop-in"

[ "$fails" = 0 ] && echo "PASS boot-good-gate"
exit $((fails > 0))
