# Building HarborPlay

Users install the DMG (see [README.md](README.md)). This page is for building from source.

## Requirements

- Apple Silicon Mac, macOS 15+, ~150 GB of free space (the disk image is sparse).
  The launcher needs Hypervisor.framework on the Mac itself: inside a macOS virtual machine (Paravirtual GPU,
  `kern.hv_vmm_present`) or without `kern.hv_support` it explains that and exits before starting the VM
  instead of reporting libkrun's `krun_start_enter failed: -22`.
- Xcode 26+ (full installation: its `actool` builds the app icon from an Icon Composer document), Homebrew, rustup.
- KosmicKrisp (optional, alternative Vulkan driver): built only on macOS 26+; `host/kosmickrisp/build.sh`
  installs its Homebrew dependencies (`llvm spirv-llvm-translator spirv-tools vulkan-loader glslang`).
- OrbStack (or Docker with arm64 and `--privileged`): the kernel, Mesa, and disk image are built in Linux containers.
- Homebrew packages: `meson ninja pkg-config dtc xz lld sshpass go` (`go`: license inventory of the bundled gvproxy/desync).
- libepoxy 1.5.10 is built from pinned sources by `host/libepoxy/build.sh`, before virglrenderer and
  libkrun; all three use `MACOSX_DEPLOYMENT_TARGET=15.0`, including on macOS 26/27 build hosts.
  Bundling rejects Mach-O deployment targets above macOS 15.0 (KosmicKrisp alone may require 26.0).

## Build and run

```sh
./build.sh          # macOS side (MoltenVK, KosmicKrisp, virglrenderer, libkrun, launcher), kernel, Mesa, disk tools
./build.sh dxmt     # optional: DXMT host executor and guest payload; then rebuild the layer and the launcher
./run.sh            # a window with SteamOS
```

Build parts separately with `./build.sh host`, `./build.sh guest`, or the scripts in the table below. Guest
artifacts carry `.inputs.json` receipts that tie them to their source inputs; `host/launcher/bundle.sh` refuses a
missing or stale one and names the step to rerun. To refresh guest artifacts without touching an existing SteamOS
disk: `guest/kernel/build.sh` (when its inputs changed), `scripts/build-image.sh builder rootfs`,
`guest/mesa/build.sh`, `scripts/build-image.sh initramfs fex layer`, then `host/launcher/build.sh`.

VM options: `./run.sh --display 1920x1080 --cpus 10 --mem 24576` (full list: `work/out/harborplay-vm --help`).

Release builds: [docs/release-build.md](docs/release-build.md).

## Source layout

| Directory | Contents |
|---|---|
| `host/moltenvk/` | MoltenVK utmapp `geometry-shaders` @05604465 + patches: depth_clip_enable, YCbCr arrays, null descriptors, geometry shader emulation for zink/DXVK (vertex stride, instancing, adjacency, fans, SCALED formats, packed vertex formats: 10-10-10-2, RG11B10F, RGB9E5, BGRA8, `gl_in`), transform feedback (DXVK stream output) and its queries (SO statistics), query result availability on copy (DXVK occlusion queries via Venus), atomics on vector components at buffer addresses (BDA, vkd3d-proton), component-packed vertex outputs under tessellation (dxil-spirv, Rift Apart), texel buffers with offsets at any texel (vkd3d-proton), writes to small push-descriptor buffers with robustness2, variable-count descriptor arrays as runtime arrays (Metal kept 32 MB per vkd3d-proton heap array and program), allocation of auxiliary buffers, deferred release of Metal resources, patch hash in the pipeline cache UUID, `VK_NULL_HANDLE` descriptor sets in binds, fragment outputs converted to their color attachment's numeric type, zeros for vertex shader inputs without a vertex attribute, integer vertex inputs read through float formats, null-checked YCbCr helper samplers, unsupported texel buffer formats rejected; tests in `repro/` run under Metal validation (also on KosmicKrisp: `REPRO_DRIVER=kosmickrisp`); `bench/run.sh <libdir>…` compares performance of changes between builds; `bench/shaders.sh <dump or pack>` measures a game's shader compilation (SPIR-V → MSL, MSL → Metal library, pipeline states; cold/warm, threads) from a MoltenVK shader dump or a 10% sample made with `bench/pack.py` |
| `host/kosmickrisp/` | KosmicKrisp (Mesa main @ce576c29) + open Mesa MRs and harborplay patches (see “Vulkan driver”), built without LLVM at runtime (`-Dllvm=disabled`, `mesa_clc` from a first build), `-Db_ndebug=true`; macOS 26+ only |
| `host/dxmt/` | Pinned DXMT + patches, static LLVM 15, native airconv, Windows DLL cross-build and guest payload; `build.sh fetch llvm native host pe client payload` |
| `wmtr/` | BSD-3-Clause winemetal remoting: guest `winemetal.so` over virtio-gpu to `libwmtr_host.dylib` (DXMT/LLVM linked in), presenting a CAMetalLayer inside the VM view |
| `host/libepoxy/` | libepoxy 1.5.10, upstream macOS Meson options, built for macOS 15.0 instead of copying a Homebrew bottle |
| `host/virglrenderer/` | virglrenderer UTM `macos-next` + merge with upstream main (venus-protocol 1.1.3) + LINEAR modifier, shm import as host memory, stubs for failed pipelines (draws dropped in virglrenderer), recreation of rejected cache, deferred shm unmap, thread QoS, Vulkan driver opened at runtime (`VKR_VULKAN_DRIVER`) |
| `host/libkrun/` | libkrun v1.19.6 + patches: `VIRTIO_GPU_F_BLOB_ALIGNMENT` (16K), SME mask for M4, 2D resources without virgl, `SET_SCANOUT_BLOB`, SHM blob mapping, Venus fence signaling, virglrenderer logs, `krun_display_resize` (resolution changes on the fly), vCPU/GPU thread QoS |
| `host/launcher/` | `harborplay-vm` (Swift/AppKit): Metal window (optional MetalFX super resolution), “HARBORPLAY” overlay with boot/shutdown progress, guest resolution = window size (× the screen's backing scale with Retina resolution) at constant DPI (EDID from the physical screen size), keyboard/mouse/tablet, the guest's Xbox 360 / DualSense / DualShock 4 pad from GameController.framework with rumble or a DualSense passed through as raw HID (`harbor.pad`), network via gvproxy, VM restart on guest reboot, `--perf-stats` |
| `guest/kernel/` | Linux 7.2.9, everything built in, 4K pages, 16K blob-node alignment, Apple TSO for FEX; uhid, hidraw and `hid-playstation` (with the LED classes it needs) for the passed-through DualSense |
| `guest/mesa/` | From the pinned Mesa: Venus ICD for aarch64 (Proton, gamescope, zink) and x86_64/i386 (FEX graphics provider); zink GL stack (libgallium, GLX/EGL/GBM) over the stock one in both, with backports in `guest/mesa/patches/` (Mesa 6abefa51: zink rebuilds the pipeline when only the vertex layout changes; without `VK_EXT_vertex_input_dynamic_state`, which Venus on Metal lacks, GL games otherwise draw with stale vertex formats); x86_64 fault reporter for emulated games (`/usr/lib/harborplay/x86_64/fault-report.so`) |
| `guest/initramfs/` | boot stage = “bootloader”: A/B slot selection with attempt counter, partsets, overlays for `/etc` and `/usr`; initial provisioning of the launcher-created disk (`harborplay.provision=1`: static mkfs.fat, mke2fs, btrfstune in initramfs); `harborplay.ssh=0` — no SSH server; launcher config payload (`harborplay.config=1`) — new `steamos` password; `harborplay.tz=` — the Mac's time zone in `/etc/localtime`; untouched procfs at `/run/harborplay/proc` for Flatpak sandboxes; `harborplay.share=` — runtime mount unit for the shared folder (virtio-fs `macshare`, see “Shared folder”) |
| `guest/layer/` | VM layer over `/usr` (read-only erofs): file-based `splctl`, safe post-install for RAUC, `VARIANT_ID=steamdeck`, gamescope session on DRM, Desktop Mode (Plasma nested in gamescope), masks for Frame hardware services, `harbor-progress-agent` progress agent (Rust, `guest/progress-agent/`, `harbor.progress` virtio-console port) and its root services (`harbor.clock`, `harbor.sleep`, the uinput or uhid gamepad on `harbor.pad`), short shutdown timeouts, QR-code Steam sign-in mode (Steam Deck client, while there is no remembered account), optional Steam client branch (`/etc/harborplay/steam-client-branch`), Steam's background shader processing on by default (`steam-shader-defaults`), Steam's idle screensaver off by default (`steam-idle-screensaver`), reset of fixed system/user manager CPU affinity masks so services inherit the VM’s available vCPUs on the next layer boot |
| `scripts/` | build of `work/out/steamos.img`: GPT with Valve's partition layout (esp, efi-A/B, rootfs-A/B, var-A/B, home); `scripts/test/provision-test-disk.sh` — dev test of provisioning against a disk from Docker; `scripts/test/vkd3d-tiled.sh` — dev end-to-end check of D3D12 tiled resources and the feature level (vkd3d-proton tests of Proton 11.0, `d3d12-caps`, `vk-minmax`) in a throwaway VM |

Easy Anti-Cheat internals: [docs/easy-anti-cheat.md](docs/easy-anti-cheat.md).
