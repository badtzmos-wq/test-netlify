param(
    [int]$Port = 8080,
    [string]$AppFolder = "BillSpliter_V2.0.1",
    [string]$EntryFile = "BillSpliter_V2.0.1.html",
    [switch]$ShowOnly
)

$ErrorActionPreference = "Stop"

function Test-PrivateIpv4Address {
    param([string]$IPAddress)

    return (
        $IPAddress -like "10.*" -or
        $IPAddress -like "192.168.*" -or
        $IPAddress -match "^172\.(1[6-9]|2[0-9]|3[0-1])\."
    )
}

function Get-LanIpv4Addresses {
    $addresses = @()

    try {
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -ne "127.0.0.1" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.PrefixOrigin -ne "WellKnown" -and
                (Test-PrivateIpv4Address $_.IPAddress)
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    } catch {
        $addresses = @()
    }

    if (-not $addresses -or $addresses.Count -eq 0) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object {
                    $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.IPAddressToString -ne "127.0.0.1" -and
                    $_.IPAddressToString -notlike "169.254.*" -and
                    (Test-PrivateIpv4Address $_.IPAddressToString)
                } |
                ForEach-Object { $_.IPAddressToString } |
                Select-Object -Unique
        } catch {
            $addresses = @()
        }
    }

    return @($addresses)
}

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$candidateDirs = @()

$candidateDirs += $rootDir

if ($AppFolder -and $AppFolder -ne ".") {
    $candidateDirs += (Join-Path $rootDir $AppFolder)
}

$siteDir = $candidateDirs |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1

if (-not $siteDir) {
    throw "App folder not found. Checked: $($candidateDirs -join ', ')"
}

$entryPath = Join-Path $siteDir $EntryFile
if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
    $fallback = Get-ChildItem -LiteralPath $siteDir -Filter *.html | Select-Object -First 1
    if (-not $fallback) {
        throw "No HTML entry file was found in: $siteDir"
    }
    $entryPath = $fallback.FullName
}

$entryName = Split-Path -Leaf $entryPath
$localUrl = "http://localhost:$Port/$entryName"
$mobileUrls = Get-LanIpv4Addresses | ForEach-Object { "http://$($_):$Port/$entryName" }

Write-Host ""
Write-Host "BillSpliter mobile server"
Write-Host "------------------------"
Write-Host "Folder : $siteDir"
Write-Host "Entry  : $entryName"
Write-Host "Local  : $localUrl"

if ($mobileUrls.Count -gt 0) {
    Write-Host ""
    Write-Host "Open one of these on your phone:"
    $mobileUrls | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host ""
    Write-Host "No private LAN IPv4 address was detected automatically."
    Write-Host "Tip: this usually means the phone cannot reach this computer by local IP."
}

Write-Host ""
Write-Host "Requirements:"
Write-Host "  1. Computer and phone must be on the same Wi-Fi."
Write-Host "  2. If Windows Firewall prompts, allow Private network access."
Write-Host "  3. Keep this window open while using the app on your phone."
Write-Host "  4. For easiest phone use, deploy this folder as a HTTPS static web app."
Write-Host ""

if ($ShowOnly) {
    return
}

Set-Location -LiteralPath $siteDir

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python -m http.server $Port --bind 0.0.0.0
    exit $LASTEXITCODE
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -m http.server $Port --bind 0.0.0.0
    exit $LASTEXITCODE
}

throw "Python was not found. Install Python or run a different local server."
