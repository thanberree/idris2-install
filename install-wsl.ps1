<#
.SYNOPSIS
  Installs the course WSL2 image (Idris2 + pack) on Windows 11.

.DESCRIPTION
  This script:
  - Ensures WSL is installed (and guides you if admin/reboot is required)
  - Downloads the prebuilt WSL export (.tar.gz)
  - Verifies SHA256
  - Decompresses to .tar
  - Imports the distribution via `wsl --import` (WSL2)

  It is designed for students who may not know WSL yet.

.RECOMMENDED ONE-LINER (PowerShell)
  # Robust student-friendly approach:
  # - downloads to a UNIQUE temp file (avoids "file is in use" collisions)
  # - runs it with ExecutionPolicy Bypass
  # - best-effort cleanup of the temp file
  $u='https://github.com/thanberree/idris2-install/releases/download/wsl-2026.01/install-wsl.ps1'; $p=Join-Path $env:TEMP ("install-wsl-{0}.ps1" -f ([guid]::NewGuid())); iwr -UseBasicParsing -Uri $u -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p; Remove-Item -Force $p -ErrorAction SilentlyContinue

.NOTES
  - If the script needs admin rights (to install WSL), it will tell you.
  - If you already have a distro named 'istic-idris', you will be prompted.
#>

[CmdletBinding()]
param(
  [string]$DistroName = 'istic-idris',
  [string]$InstallRoot = "$env:USERPROFILE\wsl",
  [string]$AssetUrl = 'https://github.com/thanberree/idris2-install/releases/download/wsl-2026.01/istic-idris-2026.01.tar.gz',
  [string]$ExpectedSha256 = '1ce1e6d77edd68484b1bb6cfa5ade10e4b27470e516282cb3b123eb60adfc456',
  [switch]$Force,
  [switch]$KeepTar,
  [switch]$KeepDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err ([string]$Message) { Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Test-IsAdmin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-WebDownload([string]$Url, [string]$OutFile) {
  Write-Info "Downloading: $Url"
  Write-Info "Saving to:  $OutFile"

  # Prefer TLS 1.2 on older Windows/PowerShell.
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch {}

  $outDir = Split-Path -Parent $OutFile
  if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  }

  if ($PSVersionTable.PSVersion.Major -lt 6) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile
  } else {
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Ensure-WslAvailable {
  $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if ($null -ne $wsl) { return }

  Write-Warn 'WSL is not installed (wsl.exe not found).'
  Write-Info 'WSL = Windows Subsystem for Linux (lets you run Linux on Windows).'

  if (-not (Test-IsAdmin)) {
    Write-Err 'Installing WSL requires Administrator rights.'
    Write-Info 'Please re-run this script in an Administrator PowerShell:'
    Write-Host '  - Start menu -> type PowerShell -> Right click -> Run as administrator' -ForegroundColor Gray
    Write-Host '  - Then run the same command again' -ForegroundColor Gray
    throw 'WSL not installed (admin required).'
  }

  Write-Info 'Installing WSL (no Linux distro from Microsoft Store will be installed by this step)...'
  & wsl.exe --install --no-distribution

  Write-Warn 'WSL installation may require a reboot.'
  Write-Info 'If asked to restart Windows, restart, then run this script again.'
  throw 'WSL install initiated; please reboot if requested, then re-run.'
}

function Ensure-Wsl2Default {
  try {
    & wsl.exe --set-default-version 2 | Out-Null
  } catch {
    # Not fatal; import can still request --version 2.
    Write-Warn 'Could not set WSL default version to 2 (continuing).'
  }
}

function Confirm-YesNo([string]$Prompt) {
  while ($true) {
    $ans = (Read-Host "$Prompt [y/N]").Trim().ToLowerInvariant()
    if ($ans -eq '' -or $ans -eq 'n' -or $ans -eq 'no') { return $false }
    if ($ans -eq 'y' -or $ans -eq 'yes') { return $true }
  }
}

function Ensure-NotAlreadyInstalled([string]$Name) {
  $existing = @()
  try {
    $existing = & wsl.exe --list --quiet 2>$null
  } catch {}

  if ($existing -contains $Name) {
    Write-Warn "A WSL distribution named '$Name' is already installed."

    if (-not $Force) {
      $ok = Confirm-YesNo "Do you want to REMOVE the existing '$Name' and replace it?"
      if (-not $ok) {
        throw "Cancelled (distribution '$Name' already exists)."
      }
    }

    Write-Info "Unregistering existing distro '$Name' (this deletes its data)..."
    & wsl.exe --unregister $Name
  }
}

function Decompress-GzipToFile([string]$GzPath, [string]$TarPath) {
  Write-Info "Decompressing to: $TarPath"

  $tarDir = Split-Path -Parent $TarPath
  if ($tarDir -and -not (Test-Path $tarDir)) {
    New-Item -ItemType Directory -Force -Path $tarDir | Out-Null
  }

  # Overwrite if present.
  if (Test-Path $TarPath) {
    Remove-Item -Force $TarPath
  }

  $in = [IO.File]::OpenRead($GzPath)
  try {
    $out = [IO.File]::Create($TarPath)
    try {
      $gzs = New-Object IO.Compression.GzipStream($in, [IO.Compression.CompressionMode]::Decompress)
      try {
        $gzs.CopyTo($out)
      } finally {
        $gzs.Dispose()
      }
    } finally {
      $out.Dispose()
    }
  } finally {
    $in.Dispose()
  }
}

try {
  Write-Host ''
  Write-Host '=== ISTIC Idris2 WSL Installer (Windows 11) ===' -ForegroundColor Green
  Write-Host ''

  Ensure-WslAvailable
  Ensure-Wsl2Default

  $installDir = Join-Path $InstallRoot $DistroName
  $downloadPath = Join-Path $env:USERPROFILE "Downloads\istic-idris-2026.01.tar.gz"
  $tarPath = Join-Path $env:TEMP 'istic-idris-2026.01.tar'

  Ensure-NotAlreadyInstalled -Name $DistroName

  $hadExistingDownload = Test-Path $downloadPath
  if (-not $hadExistingDownload) {
    Invoke-WebDownload -Url $AssetUrl -OutFile $downloadPath
  } else {
    Write-Info "Using existing download: $downloadPath"
  }

  function Verify-DownloadOrRedownload {
    Write-Info 'Verifying SHA256...'
    $actual = Get-Sha256 -Path $downloadPath
    if ($actual -eq $ExpectedSha256.ToLowerInvariant()) {
      Write-Info 'Checksum OK.'
      return
    }

    Write-Err "SHA256 mismatch. Expected: $ExpectedSha256"
    Write-Err "Actual:           $actual"

    if ($hadExistingDownload) {
      Write-Warn 'The existing downloaded file looks corrupted/incomplete. Re-downloading once...'
      try {
        Remove-Item -Force $downloadPath
      } catch {
        Write-Warn "Could not delete: $downloadPath"
        throw 'Checksum verification failed.'
      }

      $hadExistingDownload = $false
      Invoke-WebDownload -Url $AssetUrl -OutFile $downloadPath

      Write-Info 'Verifying SHA256 (second attempt)...'
      $actual2 = Get-Sha256 -Path $downloadPath
      if ($actual2 -ne $ExpectedSha256.ToLowerInvariant()) {
        Write-Err "SHA256 mismatch again. Expected: $ExpectedSha256"
        Write-Err "Actual:                $actual2"
        throw 'Checksum verification failed.'
      }
      Write-Info 'Checksum OK.'
      return
    }

    Write-Warn 'Delete the downloaded file and try again (it may be incomplete/corrupted).'
    throw 'Checksum verification failed.'
  }

  Verify-DownloadOrRedownload

  Decompress-GzipToFile -GzPath $downloadPath -TarPath $tarPath

  if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  }

  Write-Info "Importing WSL distro '$DistroName' (this can take a minute)..."
  & wsl.exe --import $DistroName $installDir $tarPath --version 2

  Write-Info 'Quick sanity check (starting the distro)...'
  try {
    & wsl.exe -d $DistroName -- uname -a | Out-Null
  } catch {
    Write-Warn 'Import succeeded but the quick check failed. You can still try: wsl -d istic-idris'
  }

  if (-not $KeepTar -and (Test-Path $tarPath)) {
    Remove-Item -Force $tarPath
  }
  if (-not $KeepDownload -and (Test-Path $downloadPath)) {
    Remove-Item -Force $downloadPath
  }

  Write-Host ''
  Write-Host 'Done.' -ForegroundColor Green
  Write-Info "Start it with: wsl -d $DistroName"
  Write-Info "List distros with: wsl -l -v"

} catch {
  Write-Host ''
  Write-Err $_.Exception.Message
  Write-Host ''
  Write-Host 'If you need help, send your teacher a screenshot of this error.' -ForegroundColor Gray
  exit 1
}
