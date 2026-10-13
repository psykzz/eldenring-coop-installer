# Elden Ring Seamless Co-op Installer

This static site provides an interactive PowerShell installer for Windows. Deploy it to GitHub
Pages using the included workflow. Users can run:

```powershell
irm https://psykzz.github.io/eldenring-coop-installer/install.ps1 | iex
```

The script defaults to Seamless Co-op 2.0.1. If a newer release is available, it offers an
arrow-key menu to use 2.0.1 or the latest release, defaulting to 2.0.1. It downloads the selected
release from
[`yuiamoroll/EldenRingSeamlessCoopRelease`](https://github.com/yuiamoroll/EldenRingSeamlessCoopRelease/releases),
checks the ZIP size and SHA-256 digest published by GitHub, validates the archive paths and
required files, then extracts the mod beside `eldenring.exe`. Existing mod files are backed up
under `%LOCALAPPDATA%\EldenRingSeamlessCoop\backups`. The installer prompts for a co-op password
and save filename, defaulting each to `crab`, while retaining every other existing setting. It then
offers to start the launcher.

The script should be reviewed before running because `irm ... | iex` executes remote code.
