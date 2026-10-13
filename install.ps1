$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Clear-Host
$Host.UI.RawUI.WindowTitle = "Seamless Co-op Installer - updated $(Get-Date -Format 'yyyy/MM/dd HH:mm')"
Write-Host @'
 d88888b db      d8888b. d88888b d8b   db       .o88b. d8888b.  .d8b.  d8888b.
 88'     88      88  `8D 88'     888o  88      d8P  Y8 88  `8D d8' `8b 88  `8D
 88ooooo 88      88   88 88ooooo 88V8o 88      8P      88oobY' 88ooo88 88oooY'
 88~~~~~ 88      88   88 88~~~~~ 88 V8o88      8b      88`8b   88~~~88 88~~~b.
 88.     88booo. 88  .8D 88.     88  V888      Y8b  d8 88 `88. 88   88 88   8D
 Y88888P Y88888P Y8888D' Y88888P VP   V8P       `Y88P' 88   YD YP   YP Y8888P'

                  SEAMLESS CO-OP INSTALLER
'@ -ForegroundColor Cyan

function Normalize-DriveLetter {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath -match '^[a-z]:') {
        return $fullPath.Substring(0, 1).ToUpperInvariant() + $fullPath.Substring(1)
    }

    return $fullPath
}

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

    $uniqueLibraries = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $normalizedLibraries = @()
    foreach ($library in $libraries | Where-Object { $_ }) {
        $normalizedLibrary = Normalize-DriveLetter -Path $library
        if ($uniqueLibraries.Add($normalizedLibrary)) {
            $normalizedLibraries += $normalizedLibrary
        }
    }

    return $normalizedLibraries
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

        Write-Host ''
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
    Write-Host ''
    $providedPath = Read-Host 'Game folder'
    if (-not (Test-Path -LiteralPath $providedPath -PathType Container)) {
        throw "Folder not found: $providedPath"
    }

    $resolvedPath = Normalize-DriveLetter -Path (Resolve-Path -LiteralPath $providedPath).Path
    if (Test-Path -LiteralPath (Join-Path $resolvedPath 'eldenring.exe') -PathType Leaf) {
        return $resolvedPath
    }

    $childGamePath = Join-Path $resolvedPath 'Game'
    if (Test-Path -LiteralPath (Join-Path $childGamePath 'eldenring.exe') -PathType Leaf) {
        return $childGamePath
    }

    throw 'The selected folder does not contain eldenring.exe or a Game subfolder containing it.'
}

function Set-SeamlessCoopSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $settingsText = [System.IO.File]::ReadAllText($Path)
    $escapedName = [regex]::Escape($Name)
    $pattern = "(?im)^(?<prefix>[ `t]*$escapedName[ `t]*=[ `t]*)[^\r\n]*?(?<suffix>[ `t]*)(?<ending>\r?)$"
    $matches = [regex]::Matches($settingsText, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Name' setting in '$Path', found $($matches.Count)."
    }

    $replacement = '$1' + $Value.Replace('$', '$$') + '$2$3'
    $updatedText = [regex]::Replace($settingsText, $pattern, $replacement, 1)
    [System.IO.File]::WriteAllText(
        $Path,
        $updatedText,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Select-MenuOption {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,
        [Parameter(Mandatory = $true)]
        [string[]] $Options,
        [int] $DefaultIndex = 0
    )

    if ($DefaultIndex -lt 0 -or $DefaultIndex -ge $Options.Count) {
        throw 'The default menu option is out of range.'
    }

    Write-Host $Prompt
    Write-Host 'Use the Up/Down arrow keys and press Enter.'
    $menuTop = [Console]::CursorTop
    $selectedIndex = $DefaultIndex
    $originalCursorVisible = [Console]::CursorVisible

    try {
        [Console]::CursorVisible = $false
        while ($true) {
            for ($index = 0; $index -lt $Options.Count; $index++) {
                [Console]::SetCursorPosition(0, $menuTop + $index)
                [Console]::Write((' ' * ([Console]::BufferWidth - 1)))
                [Console]::SetCursorPosition(0, $menuTop + $index)
                if ($index -eq $selectedIndex) {
                    [Console]::BackgroundColor = [ConsoleColor]::DarkCyan
                    [Console]::ForegroundColor = [ConsoleColor]::White
                    [Console]::Write("> $($Options[$index])")
                    [Console]::ResetColor()
                }
                else {
                    [Console]::Write("  $($Options[$index])")
                }
            }

            try {
                $key = [Console]::ReadKey($true)
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                [Console]::WriteLine('')
                throw
            }
            if ($key.Key -eq [ConsoleKey]::UpArrow) {
                $selectedIndex = ($selectedIndex + $Options.Count - 1) % $Options.Count
            }
            elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
                $selectedIndex = ($selectedIndex + 1) % $Options.Count
            }
            elseif ($key.Key -eq [ConsoleKey]::Enter) {
                [Console]::WriteLine('')
                return $selectedIndex
            }
        }
    }
    finally {
        [Console]::CursorVisible = $originalCursorVisible
    }
}

try {
    $specifiedVersion = [version]'2.0.1'
    $specifiedTag = "v$specifiedVersion"
    $releaseApi = 'https://api.github.com/repos/yuiamoroll/EldenRingSeamlessCoopRelease/releases/latest'
    $headers = @{ 'User-Agent' = 'EldenRingSeamlessCoopInstaller' }

    Write-Host 'Finding the latest Seamless Co-op release...'
    $latestRelease = Invoke-RestMethod -Uri $releaseApi -Headers $headers -Method Get
    if ($latestRelease.tag_name -notmatch '^v?(\d+\.\d+\.\d+(?:\.\d+)?)$') {
        throw "Could not parse latest release version '$($latestRelease.tag_name)'."
    }
    $latestVersion = [version]$Matches[1]

    if ($latestVersion -gt $specifiedVersion) {
        Write-Host "A newer release is available: $($latestRelease.tag_name)"
        $releaseChoice = Select-MenuOption `
            -Prompt 'Select a Seamless Co-op release:' `
            -Options @("Use specified ($specifiedVersion) [default]", 'Use latest') `
            -DefaultIndex 0
        if ($releaseChoice -eq 0) {
            $release = Invoke-RestMethod `
                -Uri "https://api.github.com/repos/yuiamoroll/EldenRingSeamlessCoopRelease/releases/tags/$specifiedTag" `
                -Headers $headers `
                -Method Get
        }
        else {
            $release = $latestRelease
        }
    }
    elseif ($latestVersion -eq $specifiedVersion) {
        $release = $latestRelease
    }
    else {
        $release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/yuiamoroll/EldenRingSeamlessCoopRelease/releases/tags/$specifiedTag" `
            -Headers $headers `
            -Method Get
    }

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
    $latestSuffix = if ($release.tag_name -eq $latestRelease.tag_name) { ' (latest)' } else { '' }
    Write-Host "Selected release: $($release.tag_name)$latestSuffix"
    Write-Host "Game folder:    $gameDirectory"
    Write-Host 'The installer will back up existing Seamless Co-op files and preserve your settings.'
    Write-Host ''
    $coopPassword = Read-Host 'Co-op password [crab]'
    if ([string]::IsNullOrEmpty($coopPassword)) {
        $coopPassword = 'crab'
    }
    $saveName = Read-Host 'Save filename [crab]'
    if ([string]::IsNullOrEmpty($saveName)) {
        $saveName = 'crab'
    }
    Write-Host ''
    $confirmation = Select-MenuOption `
        -Prompt 'Continue with installation?' `
        -Options @('Yes [default]', 'No') `
        -DefaultIndex 0
    if ($confirmation -ne 0) {
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

        Set-SeamlessCoopSetting -Path $existingSettings -Name 'cooppassword' -Value $coopPassword
        Set-SeamlessCoopSetting -Path $existingSettings -Name 'save_file_extension' -Value $saveName

        Write-Host ''
        Write-Host "Seamless Co-op $($release.tag_name) installed successfully."
        Write-Host "Co-op password and save file extension are set to '$coopPassword' and '$saveName'."
        Write-Host "Start modded sessions with: $launcherPath"
        Write-Host 'Keep the game and mod versions aligned with the other players in your party.'

        Write-Host ''
        $launchConfirmation = Select-MenuOption `
            -Prompt 'Start Seamless Co-op now?' `
            -Options @('Yes [default]', 'No') `
            -DefaultIndex 0
        if ($launchConfirmation -eq 0) {
            try {
                Start-Process -FilePath $launcherPath -WorkingDirectory $gameDirectory -ErrorAction Stop
                Write-Host 'Seamless Co-op launcher started.'
            }
            catch {
                Write-Host "Installation succeeded, but the launcher could not be started: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
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
