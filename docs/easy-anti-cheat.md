# Easy Anti-Cheat

HarborPlay sets up Easy Anti-Cheat (EAC) by itself. This page says how, and what to check when a game fails.

## The chain

```
ARM64 Steam (SteamOS guest)
 └─ Steam's FEX-Emu compatibility tool (app 3127680)
     └─ Steam Linux Runtime
         └─ Proton Experimental (x86-64)
             └─ the Windows game + the EAC Linux client (Proton EasyAntiCheat Runtime, app 1826330)
```

The x86-64 Proton runs under the FEX inside Steam's FEX-Emu tool. Replacing that FEX replaces the emulator for the
whole chain. Valve's rootfs stays unmodified: the scripts are in HarborPlay's read-only layer, and the built runtime
and its backups are in the guest's home directory.

## What HarborPlay does

`/usr/lib/harborplay/steam-fex-eac` runs before Steam starts (option **Settings > Advanced > Experimental game
support**, on by default). It finds installed games that ship EAC from their files, not from a list of titles. For
each such game it:

1. selects Proton Experimental, so Steam installs the Windows build;
2. asks Steam to install the Proton EasyAntiCheat Runtime and FEX-Emu if they are missing;
3. adds `/usr/lib/steamac/eac-launch %command%` to the game's launch options, which sets `PROTON_EAC_RUNTIME` and
   `EAC_LAUNCHERDIR` (the old path is a link to `/usr/lib/harborplay`, so launch options from older versions keep
   working);
4. installs the patched FEX into Steam's FEX-Emu tool (`fex-eac/install-fex-tool.sh`), with a backup of Valve's
   files.

With no EAC game installed, Steam's runtime is left as it is. Games without EAC and native Linux games are never
changed. After a Steam update rewrites the FEX-Emu tool, `harborplay-fex-repair.path` installs the patched FEX again.

Nothing fakes or bypasses EAC. The EAC client is the stock one from the Proton EAC Runtime and runs its own checks.

## Why Valve's FEX is not enough

EAC's Linux launcher injects its client into the game with `ptrace` and depends on exact Linux signal behaviour.
Valve's FEX does not emulate these closely enough, so the launcher never finishes and the session never
authenticates. `fex-eac/build-fex.sh` builds FEX-2610 with fidelity patches from
[Bil0000/FEX](https://github.com/Bil0000/FEX), tag `eac-2610.5`, and checks the commit (`6effd238`).

| patch | what it is |
|---|---|
| 0001 | the x86-64 view of a `ptrace` tracee, so the launcher can inject its client |
| 0002 | pages that keep faulting on self-modifying code are no longer write-protected |
| 0004 | cheaper code-range invalidation with many threads |
| 0007, 0008 | guest signal handlers run with the Linux signal mask; registers set on a syscall-entered handler stay |
| 0010 | the emulated seccomp/SIGSYS path resumes past the trapped syscall |
| 0011–0020 | kernel details a game or Wine can observe (debug registers, `/proc/<pid>/status`, `arch_prctl`, regsets, `restart_syscall`, the signal frame) |
| 0022–0026 | what an anti-tamper bootstrapper observes (host stack per SIGSYS trap, guard pages, the single-step trap after `iretq`, a thread exiting on its alt stack) |
| 0033 | `/proc/<pid>/maps` lists only the emulated process's mappings |
| 0035 | code pages the guest makes writable stay writable for other processes |

The patches make a behaviour exact only where real software observes it.

Some games need Wine's seccomp filter. For such a game, add `FEX_NEEDSSECCOMP=1` (a stock FEX option) in front of
`%command%` in its launch options.

## Check that it works

- EAC launcher log (`anticheatlauncher.log` in `EAC_LAUNCHERDIR`): `Launcher finished with: 301, 'Easy Anti-Cheat
  successfully loaded in-game'`.
- `$XDG_STATE_HOME/harborplay/fex-eac/status` in the guest: `installed`.

Never attach a debugger, `strace` or `perf` to a running EAC game. EAC reports it.

| symptom | check |
|---|---|
| launcher stops at `Starting Wine module mapping`, or the result is not `301` | the patched FEX is not installed: `sh /usr/lib/harborplay/fex-eac/install-fex-tool.sh status` |
| the game does not use Proton | restart Steam once, so the new compatibility tool applies |
| the window says "restart Steam" | a new EAC game was installed while Steam ran: restart Steam |
| the game's anti-cheat refuses virtual machines | not supported |
| stutter in new areas | shaders compile on first use; later starts are faster |

## Hardware TSO

The guest kernel uses the Apple CPU's TSO memory model (`CPU features: detected: TSO memory model (Apple)`), so FEX
pays no software cost for x86 memory ordering.
