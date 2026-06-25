Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:WindowsRoot = $PSScriptRoot
$Script:DownloadRoot = Join-Path $env:USERPROFILE ".cache\windows-setup\downloads"
$Script:ExtractRoot = Join-Path $env:USERPROFILE ".cache\windows-setup\extract"
$Script:StateRoot = Join-Path $env:USERPROFILE ".cache\windows-setup\state"

$Script:Roots = @{
    user  = $env:USERPROFILE
    apps  = Join-Path $env:USERPROFILE ".local\apps"
    bin   = Join-Path $env:USERPROFILE ".local\bin"
    cache = Join-Path $env:USERPROFILE ".cache\windows-setup"
    fonts = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
}

function Ensure-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Resolve-SetupPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match "^([^:]+):(.*)$") {
        $rootName = $Matches[1]
        $relative = $Matches[2]

        if (-not $Script:Roots.ContainsKey($rootName)) {
            throw "Unknown path root: $rootName"
        }

        if ([string]::IsNullOrWhiteSpace($relative)) {
            return $Script:Roots[$rootName]
        }

        return Join-Path $Script:Roots[$rootName] ($relative -replace "/", "\")
    }

    if ($Path.StartsWith("./")) {
        return Join-Path $Script:WindowsRoot ($Path.Substring(2) -replace "/", "\")
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $Script:WindowsRoot ($Path -replace "/", "\")
}

function Get-SafeId {
    param(
        [string]$Id,
        [Parameter(Mandatory)][string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        $Id = $Fallback
    }

    return ($Id -replace "[^A-Za-z0-9._-]", "_")
}

function Get-UrlFileName {
    param([Parameter(Mandatory)][string]$Url)

    $uri = [Uri]$Url
    $name = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Cannot infer file name from URL: $Url"
    }

    return $name
}

function Invoke-CurlDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )

    Ensure-Directory (Split-Path -Parent $OutFile)

    $args = @("-fL", "--progress-bar", "--retry", "3", "--connect-timeout", "20")
    if ($env:WINDOWS_SETUP_SOCKS) {
        $args += @("--socks5-hostname", $env:WINDOWS_SETUP_SOCKS)
    }
    $args += @("-o", $OutFile, $Url)

    Write-Host "fetching $Url ..."
    & curl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed for $Url"
    }
}

function Read-Sha256FromFile {
    param([Parameter(Mandatory)][string]$Path)

    $content = (Get-Content -Raw -Path $Path).Trim()
    if ($content -match "([A-Fa-f0-9]{64})") {
        return $Matches[1].ToLowerInvariant()
    }

    throw "No sha256 hash found in $Path"
}

function Test-Sha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    return $actual -eq $Expected.ToLowerInvariant()
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Expand-ArchiveWithTar {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Ensure-Directory $Destination

    $args = @("-xf", $Archive, "-C", $Destination)

    & tar.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed for $Archive"
    }
}

function Copy-StrippedExtractedItems {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][int]$StripComponents
    )

    $sourcePrefix = [System.IO.Path]::GetFullPath($Source).TrimEnd("\") + "\"
    $items = Get-ChildItem -LiteralPath $Source -Recurse -Force

    foreach ($item in $items) {
        $relative = $item.FullName.Substring($sourcePrefix.Length)
        $parts = $relative -split "[\\/]+"
        if ($parts.Count -le $StripComponents) {
            continue
        }

        $strippedParts = $parts[$StripComponents..($parts.Count - 1)]
        $strippedRelative = [System.IO.Path]::Combine([string[]]$strippedParts)
        $target = Join-Path $Destination $strippedRelative

        if ($item.PSIsContainer) {
            Ensure-Directory $target
        } else {
            Ensure-Directory (Split-Path -Parent $target)
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Expand-ArchiveToStaging {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$SafeId,
        [int]$StripComponents = 0
    )

    if ($StripComponents -le 0) {
        Expand-ArchiveWithTar -Archive $Archive -Destination $Destination
        return
    }

    $staging = Join-Path $Script:ExtractRoot $SafeId
    Expand-ArchiveWithTar -Archive $Archive -Destination $staging

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Ensure-Directory $Destination
    Copy-StrippedExtractedItems -Source $staging -Destination $Destination -StripComponents $StripComponents
}

function Test-AppsTarget {
    param([Parameter(Mandatory)][string]$Path)

    return $Path -match "^apps:[^\\/]+$"
}

function Get-VersionedAppPath {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Hash
    )

    $parent = Split-Path -Parent $Target
    $name = Split-Path -Leaf $Target
    return Join-Path $parent ".versioned.$name.$($Hash.Substring(0, 12))"
}

function Set-DirectoryLink {
    param(
        [Parameter(Mandatory)][string]$Link,
        [Parameter(Mandatory)][string]$Target
    )

    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ((-not $item.PSIsContainer) -and (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))) {
            throw "Refusing to replace non-directory app path: $Link"
        }
        Remove-Item -LiteralPath $Link -Recurse -Force
    }

    $relativeTarget = ".\" + (Split-Path -Leaf $Target)
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $relativeTarget | Out-Null
    } catch {
        New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
    }
}

function Install-VersionedApp {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Hash,
        [Parameter(Mandatory)][string]$SafeId,
        [int]$StripComponents = 0
    )

    $versionedTarget = Get-VersionedAppPath -Target $Target -Hash $Hash
    if (-not (Test-Path -LiteralPath $versionedTarget)) {
        Expand-ArchiveToStaging -Archive $Archive -Destination $versionedTarget -SafeId $SafeId -StripComponents $StripComponents
    }

    Set-DirectoryLink -Link $Target -Target $versionedTarget
}

function Install-UserFonts {
    param([Parameter(Mandatory)][string]$SourceDirectory)

    Ensure-Directory $Script:Roots.fonts

    $fontFiles = Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
        Where-Object { $_.Extension -in @(".ttf", ".otf", ".ttc") }

    foreach ($font in $fontFiles) {
        Write-Host "installing font $($font.Name) ..."
        $sourceHash = Get-FileSha256 -Path $font.FullName
        $target = Join-Path $Script:Roots.fonts "$($font.BaseName)-$($sourceHash.Substring(0, 12))$($font.Extension)"

        if (-not ((Test-Path -LiteralPath $target) -and (Test-Sha256 -Path $target -Expected $sourceHash))) {
            Copy-Item -LiteralPath $font.FullName -Destination $target -Force
        }

        $fontType = switch ($font.Extension.ToLowerInvariant()) {
            ".otf" { "OpenType" }
            ".ttc" { "TrueType Collection" }
            default { "TrueType" }
        }
        $regName = "$($font.BaseName) ($fontType)"

        New-ItemProperty `
            -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -Name $regName `
            -Value $target `
            -PropertyType String `
            -Force | Out-Null
    }

    Add-Type -Namespace WindowsSetup -Name NativeMethods -MemberDefinition @"
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern System.IntPtr SendMessageTimeout(
            System.IntPtr hWnd,
            uint Msg,
            System.UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out System.UIntPtr lpdwResult);
"@
    $result = [System.UIntPtr]::Zero
    [WindowsSetup.NativeMethods]::SendMessageTimeout(
        [System.IntPtr]0xffff,
        0x001D,
        [System.UIntPtr]::Zero,
        "Font",
        0x0002,
        5000,
        [ref]$result) | Out-Null
}

function Install-Archive {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$To,
        [string]$Id,
        [string]$Sha256Url,
        [ValidateSet("ImmutableUrl", "Always")][string]$Cache = "ImmutableUrl",
        [int]$StripComponents = 0,
        [switch]$InstallFont
    )

    $safeId = Get-SafeId -Id $Id -Fallback (Get-UrlFileName $Url)
    $fileName = Get-UrlFileName $Url
    $archivePath = Join-Path $Script:DownloadRoot "$safeId-$fileName"
    $hashPath = Join-Path $Script:StateRoot "$safeId.sha256"
    $target = Resolve-SetupPath $To
    $isAppsTarget = Test-AppsTarget -Path $To

    $expectedHash = $null
    if ($Sha256Url) {
        $shaFile = Join-Path $Script:StateRoot "$safeId.sha256.remote"
        Invoke-CurlDownload -Url $Sha256Url -OutFile $shaFile
        $expectedHash = Read-Sha256FromFile -Path $shaFile
    }

    $needsDownload = $Cache -eq "Always" -or -not (Test-Path -LiteralPath $archivePath)
    if ($expectedHash -and -not (Test-Sha256 -Path $archivePath -Expected $expectedHash)) {
        $needsDownload = $true
    }

    if ($needsDownload) {
        Invoke-CurlDownload -Url $Url -OutFile $archivePath
    }

    if ($expectedHash -and -not (Test-Sha256 -Path $archivePath -Expected $expectedHash)) {
        throw "sha256 mismatch for $Url"
    }

    $previousHash = if (Test-Path -LiteralPath $hashPath) {
        (Get-Content -Raw -Path $hashPath).Trim()
    } else {
        ""
    }

    $currentHash = if ($expectedHash) {
        $expectedHash
    } else {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    }

    if ($isAppsTarget) {
        Install-VersionedApp -Archive $archivePath -Target $target -Hash $currentHash -SafeId $safeId -StripComponents $StripComponents
        Set-Content -Path $hashPath -Value $currentHash
    } elseif ($previousHash -ne $currentHash -or -not (Test-Path -LiteralPath $target)) {
        Expand-ArchiveToStaging -Archive $archivePath -Destination $target -SafeId $safeId -StripComponents $StripComponents
        Set-Content -Path $hashPath -Value $currentHash
    }

    if ($InstallFont) {
        Install-UserFonts -SourceDirectory $target
    }
}

function Copy-Config {
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $source = Resolve-SetupPath $From
    $target = Resolve-SetupPath $To
    Ensure-Directory (Split-Path -Parent $target)
    Copy-Item -LiteralPath $source -Destination $target -Force
}

function Link-File {
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $source = Resolve-SetupPath $From
    $target = Resolve-SetupPath $To
    Ensure-Directory (Split-Path -Parent $target)

    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Force
    }

    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $source | Out-Null
    } catch {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

Ensure-Command curl.exe
Ensure-Command tar.exe

foreach ($root in $Script:Roots.Values) {
    Ensure-Directory $root
}
Ensure-Directory $Script:DownloadRoot
Ensure-Directory $Script:ExtractRoot
Ensure-Directory $Script:StateRoot

$index = Join-Path $Script:WindowsRoot "index.ps1"
if (-not (Test-Path -LiteralPath $index)) {
    throw "Missing index script: $index"
}

. $index
