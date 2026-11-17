# HarborPlay

Play Windows PC games from Steam on an Apple silicon Mac, including many games with Easy Anti-Cheat.

HarborPlay runs SteamOS in a small virtual machine and shows it in one Mac window. You sign in to Steam, install
games and press Play. The app picks the right setup for each game by itself: you do not choose a compatibility tool
or edit launch options.

## Requirements

| you need | notes |
|---|---|
| an Apple silicon Mac | M1 or newer |
| macOS 15 or newer | macOS 26 or newer gives the faster graphics driver |
| 16 GB of memory | less is not supported |
| free disk space | about 20 GB for SteamOS, plus room for your games |
| a Steam account | games install and run inside SteamOS |

## Install

1. Download the DMG from [Releases](https://github.com/Bil0000/harborplay/releases), open it and drag
   **HarborPlay.app** to Applications.
2. The app is not notarized. The first time, right-click it and choose **Open**, then **Open** again. If macOS does
   not offer that, open System Settings > Privacy & Security and click **Open Anyway**.
3. Click **Create New Disk…**. The app downloads Valve's SteamOS image, checks its signature and sets it up. This
   takes a while, once.
4. Allow the microphone when macOS asks. Without it, some games stutter.
5. Sign in to Steam and install your games.

Coming from FX Steam Launcher or steamac? Open HarborPlay once. It moves your settings, SteamOS disk, games, saves
and logins over by itself. You can then delete the old app.

## How it works

```
Mac window  ─▶  SteamOS VM  ─▶  Steam  ─▶  Proton  ─▶  Windows game
 (Metal)        (libkrun)                  (Wine)       (x86-64, run by FEX)
```

- **The VM.** SteamOS runs in a light virtual machine (libkrun) with its own disk image, so it never touches your
  Mac's drive layout. Quitting the app shuts SteamOS down.
- **x86 games on an ARM Mac.** SteamOS runs Windows games through Proton. FEX translates their x86-64 code to the
  Mac's ARM code.
- **Graphics.** Games draw with Vulkan inside the VM. The Mac side turns that into Metal, through KosmicKrisp
  (macOS 26) or MoltenVK. Direct3D 11 games can also use DXMT, which talks to Metal more directly.
- **Easy Anti-Cheat.** When you install a game that ships Easy Anti-Cheat, HarborPlay sets it up: a FEX build that
  passes EAC's checks, Proton Experimental, the Proton EasyAntiCheat Runtime and a launch helper. Nothing is faked
  or bypassed; EAC runs its own unmodified checks. Games without EAC, and native Linux games such as Counter-Strike 2
  and Dota 2, are left alone.
- **Updates.** SteamOS updates itself as on a Steam Deck. If a new SteamOS build does not reach Steam, the next
  start goes back to the last build that worked.

## Games

- Most games that run on a Steam Deck run here. Performance depends on the game and your Mac.
- Easy Anti-Cheat works per game: each game ships its own EAC version and rules. Bodycam is tested. Games whose
  anti-cheat refuses virtual machines will not run.
- The first start of a game compiles shaders, so it can stutter for a few minutes. Later starts are faster.

## Settings worth knowing

- **Settings > Display**: window size and MetalFX upscaling.
- **Settings > Advanced > Experimental game support**: the automatic Easy Anti-Cheat setup. On by default.
- **Settings > Games**: per-game graphics path (Vulkan or DXMT).

HarborPlay sends no crash reports and no statistics. At startup it asks GitHub for a new version; turn this off in
Settings > General > Check for updates at startup.

## Build from source

```sh
./build.sh          # macOS side, guest kernel, Mesa, layer and disk tools
./build.sh dxmt     # optional DXMT path
./run.sh            # open a window with SteamOS
```

Needs Xcode, Homebrew, rustup and Docker (OrbStack works). Details: [SETUP.md](SETUP.md) and
[docs/release-build.md](docs/release-build.md).

## Uninstall

1. Quit HarborPlay and move it to the Trash.
2. In Terminal:
   ```
   rm -rf ~/Library/Application\ Support/io.github.bil0000.harborplay ~/Library/Caches/io.github.bil0000.harborplay \
          ~/Library/Logs/io.github.bil0000.harborplay
   defaults delete io.github.bil0000.harborplay
   ```
   If you came from the old app, also run:
   ```
   rm -rf ~/Library/Application\ Support/es.fxgam.steamac ~/Library/Caches/es.fxgam.steamac ~/Library/Logs/es.fxgam.steamac
   defaults delete es.fxgam.steamac
   security delete-generic-password -s es.fxgam.steamac.guest-password
   ```
   The last command removes one saved SteamOS password per run; repeat it until it says it found none.

## Licence

Apache-2.0, with some parts under GPL-2.0, LGPL-2.1, MIT and BSD-3-Clause. [NOTICE](NOTICE) lists each part, its
licence and the people and projects it comes from. SteamOS is not included: the app downloads it from Valve after you
accept Valve's licence. Not affiliated with Valve.
