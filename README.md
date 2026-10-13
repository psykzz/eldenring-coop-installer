# Elden Ring Seamless Co-op Installer

This static site provides an interactive PowerShell installer for Windows. Deploy it to GitHub
Pages using the included workflow. Users can run:

```powershell
irm https://psykzz.github.io/eldenring-coop-installer/install.ps1 | iex
```

The script defaults to Seamless Co-op 2.0.1. If a newer release is available, it offers an
left/right-arrow menu to use 2.0.1 or the latest release, defaulting to 2.0.1. It downloads the selected
release from
[`yuiamoroll/EldenRingSeamlessCoopRelease`](https://github.com/yuiamoroll/EldenRingSeamlessCoopRelease/releases),
checks the ZIP size and SHA-256 digest published by GitHub, validates the archive paths and
required files, then extracts the mod beside `eldenring.exe`. Existing mod files are backed up
under `%LOCALAPPDATA%\EldenRingSeamlessCoop\backups`. The installer prompts for a co-op password
and save filename, defaulting each to `crab`, while retaining every other existing setting. It then
offers to copy base-game `.sl2` saves from `%APPDATA%\EldenRing` to `.<savefilename>` copies
before optionally starting the launcher. Each `.sl2` file contains all character slots, so the
count shown is the number of files, not individual characters. Original `.sl2` saves are never
changed or deleted, and existing destination copies are left untouched.
Before launch, the installer offers to create a `Seamless Co-op` shortcut on the Windows desktop
if that shortcut does not already exist.

The script should be reviewed before running because `irm ... | iex` executes remote code.
