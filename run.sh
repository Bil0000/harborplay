#!/usr/bin/env bash
# Boot SteamOS in a window. Extra arguments go to harborplay-vm (see `work/out/harborplay-vm --help`),
# e.g. ./run.sh --display 1920x1080 --cpus 10 --mem 24576
set -euo pipefail
out="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/work/out"
exec "$out/harborplay-vm" \
    --kernel "$out/Image" \
    --initrd "$out/initramfs.cpio.gz" \
    --disk "$out/steamos.img" \
    --disk "$out/harborplay-layer.img:ro" \
    "$@"
