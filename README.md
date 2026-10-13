# Elden Ring Seamless Co-op Installer

This static site provides an interactive PowerShell installer for Windows. Deploy it to GitHub
Pages using the included workflow. Users can run:

```powershell
irm https://psykzz.github.io/eldenring-coop-installer/install.ps1 | iex
```

GitHub Pages does not support `_redirects` or custom response headers. The `_redirects` and
`_headers` files are retained for static hosts that support them, allowing the originally intended
`/install` route when deployed there. To use `https://eldenring-coop.neeko.psykzz.com/install`,
configure that custom domain in GitHub Pages and point its DNS to GitHub Pages; note that GitHub
Pages cannot provide the `/install` rewrite by itself.

The script queries the latest release from
[`yuiamoroll/EldenRingSeamlessCoopRelease`](https://github.com/yuiamoroll/EldenRingSeamlessCoopRelease/releases),
checks the ZIP size and SHA-256 digest published by GitHub, validates the archive paths and
required files, then extracts the mod beside `eldenring.exe`. Existing mod files are backed up
under `%LOCALAPPDATA%\EldenRingSeamlessCoop\backups`; an existing `ersc_settings.ini` is retained.

The script should be reviewed before running because `irm ... | iex` executes remote code.
