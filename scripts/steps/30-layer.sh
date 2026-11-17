#!/bin/bash
# Step 30 (builder container): work/out/harborplay-layer.img
# Read-only erofs image; its usr/ becomes the top lowerdir of the guest /usr
# overlay (lowerdir=<layer>/usr:<rootfs>/usr), see guest/initramfs/init.
# Contents: guest/layer/usr (harborplay files) + work/out/mesa-venus/usr (Venus
# ICDs, the patched zink GL stack and the x86_64 fault reporter from
# guest/mesa; required unless ALLOW_NO_VENUS=1) + the harbor-progress-agent binary
# built by step 25 from guest/progress-agent + the patched FEX stage built by
# step 27.
set -euo pipefail
. /src/scripts/config.env

OUT=/work/out/harborplay-layer.img
VENUS=/work/out/mesa-venus
ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT

cp -a /src/guest/layer/usr "$ST/usr"
# Local test runs leave Python caches (with the build machine's paths) in the source tree.
find "$ST/usr" -name __pycache__ -prune -exec rm -rf {} +
install -d "$ST/usr/lib/harborplay/fex-eac"
for file in build-fex.sh install-fex-tool.sh; do
    install -m 0755 "/src/fex-eac/$file" "$ST/usr/lib/harborplay/fex-eac/$file"
done
# Prebuilt runtime: steam-fex-eac installs it when its receipt names build-fex.sh's FEX_EAC_SHA.
FEX=/work/out/fex-eac/stage
fex_sha=$(sed -n 's/^FEX_EAC_SHA=//p' /src/fex-eac/build-fex.sh)
[[ $(cat "$FEX/.steamac-fex-source" 2>/dev/null) == "$fex_sha" ]] \
    || { echo "[layer] $FEX is missing or not FEX $fex_sha: run scripts/build-image.sh fex" >&2; exit 1; }
cp -a "$FEX" "$ST/usr/lib/harborplay/fex-eac/stage"
for f in FEXCompatTool usr/bin/FEX usr/bin/FEXServer; do
    [[ $(od -An -tx1 -N20 "$ST/usr/lib/harborplay/fex-eac/stage/$f" | tr -d ' \n') == 7f454c46020101*b700 ]] \
        || { echo "[layer] fex-eac/stage/$f is not an aarch64 ELF" >&2; exit 1; }
done

if [[ -d $VENUS/usr ]]; then
    cp -a "$VENUS/usr/." "$ST/usr/"
    [[ -f $ST/usr/lib/harborplay/x86_64/fault-report.so ]] \
        || { echo "[layer] $VENUS lacks usr/lib/harborplay/x86_64/fault-report.so: rebuild guest/mesa (x86 step)" >&2; exit 1; }
    venus_info=$(cd "$VENUS/usr" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)
    echo "[layer] included Venus tree from $VENUS ($venus_info)"
elif [[ ${ALLOW_NO_VENUS:-} == 1 ]]; then
    venus_info="ABSENT (ALLOW_NO_VENUS=1)"
    echo "[layer] WARNING: $VENUS/usr missing, building layer WITHOUT Venus (ALLOW_NO_VENUS=1)" >&2
else
    echo "[layer] $VENUS/usr missing: build guest/mesa first (or ALLOW_NO_VENUS=1 for a test layer)" >&2
    exit 1
fi

# DXMT for the launcher's D3D11 on Metal setting (steam-gfx-path): DXMT's PE dlls (Wine builtins:
# d3d11, dxgi, d3d10core, winemetal) and the wmtr guest client winemetal.so, staged in /work/out/dxmt by
# host/dxmt/build.sh. Optional: without it the layer offers only the Vulkan path.
DXMT=/work/out/dxmt
dxmt_info=ABSENT
for arch in x86_64 aarch64; do
    if [[ -f $DXMT/$arch-unix/winemetal.so ]]; then
        install -d "$ST/usr/lib/harborplay/dxmt/$arch-windows" "$ST/usr/lib/harborplay/dxmt/$arch-unix"
        for f in d3d11 dxgi d3d10core winemetal; do
            install -m 0644 "$DXMT/$arch-windows/$f.dll" "$ST/usr/lib/harborplay/dxmt/$arch-windows/$f.dll"
        done
        install -m 0644 "$DXMT/$arch-unix/winemetal.so" "$ST/usr/lib/harborplay/dxmt/$arch-unix/winemetal.so"
    fi
done
if [[ -d $ST/usr/lib/harborplay/dxmt ]]; then
    dxmt_info=$(cd "$DXMT" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)
    echo "[layer] included DXMT from $DXMT ($dxmt_info)"
fi

AGENT=/work/cache/progress-agent/harbor-progress-agent
[[ -x $AGENT ]] || { echo "[layer] $AGENT missing: run step 25 (scripts/build-image.sh layer does)" >&2; exit 1; }
install -m 0755 "$AGENT" "$ST/usr/lib/harborplay/harbor-progress-agent"
for target in gamescope-session.target plasma-session.target; do
    [[ -L $ST/usr/lib/systemd/user/$target.wants/harbor-progress-agent.service ]] \
        || { echo "[layer] harbor-progress-agent.service is not wanted by $target" >&2; exit 1; }
    [[ -L $ST/usr/lib/systemd/user/$target.wants/harbor-clipboard-agent.service ]] \
        || { echo "[layer] harbor-clipboard-agent.service is not wanted by $target" >&2; exit 1; }
done
# Desktop Mode: the stock plasma-session.target (its SteamVR units are masked);
# gamescope-session runs the nested desktop, whose Steam autostart keeps the
# selected client.
[[ -f $ST/usr/lib/systemd/user/harborplay-nested-desktop.service ]] \
    && grep -q 'harborplay-nested-desktop.service' "$ST/usr/lib/steamos/gamescope-session" \
    && grep -q '^Exec=/usr/lib/harborplay/steam-client --desktop' "$ST/usr/lib/harborplay/desktop-xdg/autostart/steam.desktop" \
    || { echo "[layer] Desktop Mode units (harborplay-nested-desktop.service, Steam autostart) missing" >&2; exit 1; }
# Same binary, root mode: started by udev for the launcher's harbor.clock port.
grep -q 'harbor-progress-agent clock-sync' "$ST/usr/lib/systemd/system/harbor-clock-sync.service" \
    && grep -q 'harbor-clock-sync.service' "$ST/usr/lib/udev/rules.d/70-harbor-progress.rules" \
    || { echo "[layer] harbor-clock-sync.service / its udev rule missing" >&2; exit 1; }
# Same binary, root mode: the gamepad, started by udev for the launcher's harbor.pad port.
grep -q 'harbor-progress-agent pad$' "$ST/usr/lib/systemd/system/harbor-pad.service" \
    && grep -q 'harbor-pad.service' "$ST/usr/lib/udev/rules.d/70-harbor-progress.rules" \
    || { echo "[layer] harbor-pad.service / its udev rule missing" >&2; exit 1; }
# ... and one instance per further player's port (harbor.pad2, ...).
grep -q 'harbor-progress-agent pad$' "$ST/usr/lib/systemd/system/harbor-pad@.service" \
    && grep -q 'HARBOR_PAD_PORT=/dev/virtio-ports/%i$' "$ST/usr/lib/systemd/system/harbor-pad@.service" \
    && grep -q 'harbor-pad@\$attr{name}.service' "$ST/usr/lib/udev/rules.d/70-harbor-progress.rules" \
    || { echo "[layer] harbor-pad@.service / its udev rule missing" >&2; exit 1; }
# Same binary as systemd-suspend.service's ExecStart: the launcher pauses the VM instead.
grep -q 'harbor-progress-agent sleep suspend$' "$ST/usr/lib/systemd/system/systemd-suspend.service.d/50-harborplay-sleep.conf" \
    || { echo "[layer] systemd-suspend.service drop-in (harbor-progress-agent sleep) missing" >&2; exit 1; }
# Reclaim Mac SSD space: path unit watches the agent's request file, oneshot runs fstrim as root.
[[ -x $ST/usr/lib/harborplay/compact-disk ]] \
    && [[ -f $ST/usr/lib/systemd/system/harbor-compact-disk.service \
          && -f $ST/usr/lib/systemd/system/harbor-compact-disk.path ]] \
    && [[ -L $ST/usr/lib/systemd/system/multi-user.target.wants/harbor-compact-disk.path ]] \
    && grep -q '^ExecStart=/usr/lib/harborplay/compact-disk$' "$ST/usr/lib/systemd/system/harbor-compact-disk.service" \
    && grep -q '^PathExists=/home/steamos/.local/share/harborplay/compact-request$' \
        "$ST/usr/lib/systemd/system/harbor-compact-disk.path" \
    || { echo "[layer] harbor-compact-disk (compact-disk script / path+service / multi-user wants) missing" >&2; exit 1; }

# Experimental game support: repair the runtime after Steam rewrites its FEX-Emu tool while it runs.
for target in gamescope-session.target plasma-session.target; do
    [[ -L $ST/usr/lib/systemd/user/$target.wants/harborplay-fex-repair.path ]] \
        || { echo "[layer] harborplay-fex-repair.path is not wanted by $target" >&2; exit 1; }
done
grep -q '^ExecStart=/usr/lib/harborplay/steam-fex-eac repair$' "$ST/usr/lib/systemd/user/harborplay-fex-repair.service" \
    || { echo "[layer] harborplay-fex-repair.service does not run steam-fex-eac repair" >&2; exit 1; }
# Once per boot: drop the boot's clean page cache so free page reporting returns it to the Mac.
[[ -L $ST/usr/lib/systemd/system/timers.target.wants/harborplay-mem-trim.timer ]] \
    && grep -q '^ExecStart=/usr/lib/harborplay/mem-trim$' "$ST/usr/lib/systemd/system/harborplay-mem-trim.service" \
    || { echo "[layer] harborplay-mem-trim timer/service missing" >&2; exit 1; }
# Sanity: the pieces the initramfs and the A/B flow depend on.
for f in usr/bin/splctl usr/lib/rauc/post-install.sh usr/lib/harborplay/kernelsetup.sh \
         usr/lib/harborplay/rauc-shims/steamos-chroot usr/lib/harborplay/steam-gfx-env \
         usr/lib/harborplay/steam-shader-defaults usr/lib/harborplay/steam-client usr/lib/harborplay/steam-gfx-path \
         usr/lib/harborplay/nested-desktop usr/lib/harborplay/steam-frame-latency usr/lib/harborplay/steam-launch-app usr/lib/harborplay/steam-install-tools usr/lib/harborplay/mem-trim usr/lib/harborplay/steam-ui-gpu \
         usr/lib/harborplay/desktop-bin/kwin_wayland_wrapper \
         usr/lib/harborplay/desktop-bin/steamosctl usr/lib/steamos/gamescope-session \
         usr/lib/harborplay/compact-disk usr/lib/harborplay/boot-good-gate; do
    [[ -x $ST/$f ]] || { echo "[layer] $f missing or not executable" >&2; exit 1; }
    bash -n "$ST/$f"
done
# steam-gfx-path's Python helper (Proton Experimental as Steam's default tool while DXMT is on).
[[ -x $ST/usr/lib/harborplay/steam-compat-default ]] \
    || { echo "[layer] usr/lib/harborplay/steam-compat-default missing or not executable" >&2; exit 1; }
[[ -x $ST/usr/lib/harborplay/steam-dxmt-arm64ec ]] \
    || { echo "[layer] usr/lib/harborplay/steam-dxmt-arm64ec missing or not executable" >&2; exit 1; }
[[ -f $ST/usr/lib/systemd/user/steam.service.d/50-harborplay.conf ]] \
    || { echo "[layer] steam.service drop-in missing" >&2; exit 1; }
[[ ! -e $ST/usr/lib/systemd/user/steam.service && ! -e $ST/usr/share/deckard/RUNSTEAM.sh ]] \
    || { echo "[layer] proprietary stock Steam files must not be overlaid" >&2; exit 1; }
grep -q 'ExecStartPre=/usr/lib/harborplay/steam-client' "$ST/usr/lib/systemd/user/steam.service.d/50-harborplay.conf" \
    && grep -q 'ExecStartPost=/usr/lib/harborplay/steam-client --watch' "$ST/usr/lib/systemd/user/steam.service.d/50-harborplay.conf" \
    || { echo "[layer] steam.service client setup or watcher missing" >&2; exit 1; }
ls "$ST"/usr/lib/harborplay/masks.d/*.list >/dev/null
grep -q 'ExecStartPre=-/usr/lib/harborplay/steam-gfx-path' "$ST/usr/lib/systemd/user/steam.service.d/50-harborplay.conf" \
    && grep -q '^ExecStart=/usr/lib/harborplay/steam-gfx-path --watch$' "$ST/usr/lib/systemd/user/harborplay-gfx-path.service" \
    && [[ -L $ST/usr/lib/systemd/user/gamescope-session.target.wants/harborplay-gfx-path.service \
          && -L $ST/usr/lib/systemd/user/plasma-session.target.wants/harborplay-gfx-path.service ]] \
    || { echo "[layer] steam-gfx-path (steam.service ExecStartPre, harborplay-gfx-path.service) missing" >&2; exit 1; }
grep -q 'ExecStartPre=-/usr/lib/harborplay/steam-frame-latency' "$ST/usr/lib/systemd/user/steam.service.d/50-harborplay.conf" \
    || { echo "[layer] steam-frame-latency (steam.service ExecStartPre) missing" >&2; exit 1; }

# Manager drop-ins must survive staging (including the Venus merge). The
# initramfs mounts this /usr before starting PID 1; no /etc modification needed.
for manager in system user; do
    conf=usr/lib/systemd/$manager.conf.d/99-harborplay-vcpu-affinity.conf
    cmp "/src/guest/layer/$conf" "$ST/$conf" \
        || { echo "[layer] $conf missing or overwritten" >&2; exit 1; }
done

# layer-release: content hash (excluding itself) so a boot log identifies the layer.
tree_hash=$(cd "$ST" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)
cat > "$ST/usr/lib/harborplay/layer-release" <<EOF
harborplay-layer content=$tree_hash rootfs-pin=$STEAMOS_BUILDID venus=$venus_info dxmt=$dxmt_info
EOF

# Directory/file modes come from the repo checkout; normalise and make root-owned.
find "$ST" -type d -exec chmod 0755 {} +
find "$ST" -type f -perm -u+x -exec chmod 0755 {} +
find "$ST" -type f ! -perm -u+x -exec chmod 0644 {} +

epoch=${SOURCE_DATE_EPOCH:-1767225600}
rm -f "$OUT.tmp"
mkfs.erofs -zlz4hc -T "$epoch" -U 5fea1f2a-0c6b-4d5e-9a1e-0000000000a1 --all-root -L harbor-layer "$OUT.tmp" "$ST" >/dev/null
mv "$OUT.tmp" "$OUT"
echo "[layer] $OUT: $(stat -c %s "$OUT") bytes; $(cat "$ST/usr/lib/harborplay/layer-release")"
