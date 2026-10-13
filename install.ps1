$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SteamLibraryPaths {
    $steamRoots = @()
    $registryLocations = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )

    foreach ($location in $registryLocations) {
        $properties = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
        if ($properties) {
            foreach ($name in @('SteamPath', 'InstallPath')) {
                $property = $properties.PSObject.Properties[$name]
                if ($property -and $property.Value) {
                    $steamRoots += $property.Value
                }
            }
        }
    }

    $libraries = @($steamRoots)
    foreach ($steamRoot in $steamRoots) {
        $vdfPath = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdfPath -PathType Leaf) {
            $vdfContent = Get-Content -LiteralPath $vdfPath -Raw
            foreach ($match in [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value -replace '\\\\', '\'
            }
        }
    }

    return @($libraries | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-GameDirectory {
    $candidates = @(
        Get-SteamLibraryPaths | ForEach-Object {
            Join-Path $_ 'steamapps\common\ELDEN RING\Game'
        } | Where-Object {
            Test-Path -LiteralPath (Join-Path $_ 'eldenring.exe') -PathType Leaf
        }
    )

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    if ($candidates.Count -gt 1) {
        Write-Host 'Found multiple Elden Ring installations:'
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            Write-Host "  [$($index + 1)] $($candidates[$index])"
        }

        $selection = Read-Host "Choose an installation (1-$($candidates.Count))"
        $selectedIndex = 0
        if (-not [int]::TryParse($selection, [ref]$selectedIndex) -or
            $selectedIndex -lt 1 -or $selectedIndex -gt $candidates.Count) {
            throw 'Invalid installation selection.'
        }

        return $candidates[$selectedIndex - 1]
    }

    Write-Host 'Could not find the game automatically.'
    Write-Host 'Enter the Game folder containing eldenring.exe, or its parent ELDEN RING folder.'
    $providedPath = Read-Host 'Game folder'
    if (-not (Test-Path -LiteralPath $providedPath -PathType Container)) {
        throw "Folder not found: $providedPath"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $providedPath).Path
    if (Test-Path -LiteralPath (Join-Path $resolvedPath 'eldenring.exe') -PathType Leaf) {
        return $resolvedPath
    }

    $childGamePath = Join-Path $resolvedPath 'Game'
    if (Test-Path -LiteralPath (Join-Path $childGamePath 'eldenring.exe') -PathType Leaf) {
        return $childGamePath
    }

    throw 'The selected folder does not contain eldenring.exe or a Game subfolder containing it.'
}

try {
    $releaseApi = 'https://api.github.com/repos/yuiamoroll/EldenRingSeamlessCoopRelease/releases/latest'
    $headers = @{ 'User-Agent' = 'EldenRingSeamlessCoopInstaller' }

    Write-Host 'Finding the latest Seamless Co-op release...'
    $release = Invoke-RestMethod -Uri $releaseApi -Headers $headers -Method Get
    $assets = @($release.assets | Where-Object { $_.name -match '^Seamless\.Co-op\..+\.zip$' })
    if ($assets.Count -ne 1) {
        throw "Expected one Seamless Co-op ZIP in release '$($release.tag_name)', found $($assets.Count)."
    }

    $asset = $assets[0]
    if ($asset.browser_download_url -notmatch '^https://github\.com/') {
        throw 'The release asset URL is not an HTTPS GitHub download.'
    }
    if ($asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'The release does not provide a SHA-256 digest; refusing to install an unverifiable archive.'
    }
    $expectedHash = $Matches[1].ToUpperInvariant()

    $gameDirectory = Get-GameDirectory
    if (Get-Process -Name eldenring, ersc_launcher -ErrorAction SilentlyContinue) {
        throw 'Close Elden Ring and ersc_launcher before installing the mod.'
    }

    Write-Host ''
    Write-Host "Latest release: $($release.tag_name)"
    Write-Host "Game folder:    $gameDirectory"
    Write-Host 'The installer will back up existing Seamless Co-op files and preserve your settings.'
    $confirmation = Read-Host 'Continue? [y/N]'
    if ($confirmation -notmatch '^(y|yes)$') {
        Write-Host 'Installation cancelled.'
        return
    }

    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        'EldenRingSeamlessCoop-' + [guid]::NewGuid().ToString('N')
    )
    New-Item -Path $workDirectory -ItemType Directory -Force | Out-Null

    try {
        $archivePath = Join-Path $workDirectory $asset.name
        $extractDirectory = Join-Path $workDirectory 'extracted'
        New-Item -Path $extractDirectory -ItemType Directory | Out-Null

        Write-Host 'Downloading the release archive...'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -Headers $headers -UseBasicParsing

        if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$asset.size) {
            throw 'Downloaded archive size does not match the GitHub release metadata.'
        }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw 'Downloaded archive SHA-256 does not match the GitHub release metadata.'
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $extractRoot = [System.IO.Path]::GetFullPath($extractDirectory) +
                [System.IO.Path]::DirectorySeparatorChar
            foreach ($entry in $zip.Entries) {
                $entryPath = [System.IO.Path]::GetFullPath(
                    (Join-Path $extractDirectory $entry.FullName)
                )
                if (-not $entryPath.StartsWith(
                    $extractRoot,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                    throw "Unsafe path in release archive: $($entry.FullName)"
                }
            }
        }
        finally {
            $zip.Dispose()
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDirectory -Force
        $requiredFiles = @(
            'ersc_launcher.exe',
            'SeamlessCoop\ersc.dll',
            'SeamlessCoop\ersc_settings.ini'
        )
        foreach ($relativePath in $requiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $extractDirectory $relativePath) -PathType Leaf)) {
                throw "Release archive is missing the expected file: $relativePath"
            }
        }

        $launcherPath = Join-Path $gameDirectory 'ersc_launcher.exe'
        $modDirectory = Join-Path $gameDirectory 'SeamlessCoop'
        $existingSettings = Join-Path $modDirectory 'ersc_settings.ini'
        $hasExistingMod = (Test-Path -LiteralPath $launcherPath) -or
            (Test-Path -LiteralPath $modDirectory)
        $settingsBackupPath = Join-Path $workDirectory 'ersc_settings.ini'
        if (Test-Path -LiteralPath $existingSettings -PathType Leaf) {
            Copy-Item -LiteralPath $existingSettings -Destination $settingsBackupPath
        }

        if ($hasExistingMod) {
            $backupDirectory = Join-Path $env:LOCALAPPDATA (
                'EldenRingSeamlessCoop\backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            )
            New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
            if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
                Copy-Item -LiteralPath $launcherPath -Destination $backupDirectory
            }
            if (Test-Path -LiteralPath $modDirectory -PathType Container) {
                Copy-Item -LiteralPath $modDirectory -Destination $backupDirectory -Recurse
            }
            Write-Host "Existing files backed up to: $backupDirectory"
        }

        if (Test-Path -LiteralPath $modDirectory) {
            Remove-Item -LiteralPath $modDirectory -Recurse -Force
        }
        Copy-Item -LiteralPath (Join-Path $extractDirectory 'ersc_launcher.exe') -Destination $gameDirectory
        Copy-Item -LiteralPath (Join-Path $extractDirectory 'SeamlessCoop') -Destination $gameDirectory -Recurse

        if (Test-Path -LiteralPath $settingsBackupPath -PathType Leaf) {
            Copy-Item -LiteralPath $settingsBackupPath -Destination $existingSettings -Force
        }

        Write-Host ''
        Write-Host "Seamless Co-op $($release.tag_name) installed successfully."
        Write-Host "Start modded sessions with: $launcherPath"
        Write-Host 'Keep the game and mod versions aligned with the other players in your party.'
    }
    finally {
        if (Test-Path -LiteralPath $workDirectory) {
            Remove-Item -LiteralPath $workDirectory -Recurse -Force
        }
    }
}
catch {
    $message = "Seamless Co-op installation failed: $($_.Exception.Message)"
    Write-Host $message -ForegroundColor Red
    throw $message
}
