#!/bin/sh
# Runs inside harborplay-kernel-builder (native arm64). Invoked by build.sh.
# Mounts: /harborplay = guest/kernel (ro), /cache = kernel tarball dir (ro),
#         /out = work/out (rw), /build = docker volume (case-sensitive work area).
set -eu
: "${KVER:?}" "${JOBS:?}"

src=/build/linux-$KVER
obj=/build/obj-$KVER
tarball=/cache/linux-$KVER.tar.xz
make_args="-C $src O=$obj ARCH=arm64 KBUILD_BUILD_USER=harborplay KBUILD_BUILD_HOST=harborplay"

# Source tree: (re)extract + patch whenever the tarball or a patch changes.
stamp=$(cat "$tarball" /harborplay/patches/*.patch | sha256sum | cut -d' ' -f1)
if [ "$(cat "$src/.harborplay-stamp" 2>/dev/null || true)" != "$stamp" ]; then
	echo ">> extracting $tarball"
	rm -rf "$src" "$obj"
	tar -C /build -xf "$tarball"
	for p in /harborplay/patches/*.patch; do
		echo ">> applying $(basename "$p")"
		patch -d "$src" -p1 -F0 --no-backup-if-mismatch < "$p"
	done
	echo "$stamp" > "$src/.harborplay-stamp"
fi
mkdir -p "$obj"

# Config: libkrunfw base + Frame userspace options + harborplay requirements.
echo ">> configuring"
cp /harborplay/config/00-base-libkrunfw-aarch64.config "$obj/.config"
"$src/scripts/kconfig/merge_config.sh" -m -O "$obj" "$obj/.config" \
	/harborplay/config/10-frame-userspace.config /harborplay/config/20-harborplay.config \
	> "$obj/merge_config.log"
make $make_args olddefconfig > /dev/null
# Everything built in: promote modules until Kconfig settles.
i=0
while grep -qE '^CONFIG_[A-Za-z0-9_]+=m$' "$obj/.config" && [ $i -lt 10 ]; do
	sed -i -E 's/^(CONFIG_[A-Za-z0-9_]+)=m$/\1=y/' "$obj/.config"
	make $make_args olddefconfig > /dev/null
	i=$((i + 1))
done
sh /harborplay/check-config.sh "$obj/.config" /harborplay/config/20-harborplay.config > "$obj/check-config.log" || {
	cat "$obj/check-config.log"
	exit 1
}
tail -n1 "$obj/check-config.log"

echo ">> building Image with -j$JOBS"
make $make_args -j"$JOBS" Image
# temp + rename: a VM booting meanwhile reads either the old or the new Image, never half.
cp "$obj/arch/arm64/boot/Image" /out/Image.tmp
mv -f /out/Image.tmp /out/Image
cp "$obj/.config" /out/kernel.config
cp "$obj/check-config.log" /out/kernel-check-config.log
echo ">> $(cat "$obj/include/config/kernel.release")"
