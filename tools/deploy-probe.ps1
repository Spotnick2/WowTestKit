<#
    deploy-probe.ps1 - Deploy WowTestKitProbe, a ForeverProbe module (/fp tk),
    for the in-game measurements behind the core's models.

    In order, each step stopping the rest if it refuses:
      1. ForeverProbe, the host (..\ForeverProbe, or $env:FOREVERPROBE), with its own deploy;
      2. the module's TOC and Lua. A file the module no longer ships is removed
         from the addon's folder.

    In game, /reload loads it, a brand-new addon folder included
    (PORTING-TBC-TO-FOREVER.md, section 5).

        pwsh tools/deploy-probe.ps1
        pwsh tools/deploy-probe.ps1 -AddOnsPath "D:\...\_forever_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "WowTestKitProbe"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ForeverProbe = if ($env:FOREVERPROBE) { $env:FOREVERPROBE } else { Join-Path (Split-Path -Parent $RepoRoot) "ForeverProbe" }
$Files = @("WowTestKitProbe.toc", "WowTestKitProbe.lua")

foreach ($f in $Files) {
    if (-not (Test-Path -LiteralPath (Join-Path $src $f))) { Write-Error "Missing probe file: $f"; exit 1 }
}
$luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
if (Test-Path -LiteralPath $luac) {
    & $luac -p (Join-Path $src "WowTestKitProbe.lua")
    if ($LASTEXITCODE -ne 0) { Write-Error "luac -p failed on the probe's Lua"; exit 1 }
    Remove-Item -LiteralPath "luac.out" -ErrorAction SilentlyContinue
} else {
    Write-Host "  luac -p SKIPPED (no $luac)" -ForegroundColor Yellow
}
if (-not (Test-Path -LiteralPath $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }
$AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath).ProviderPath

# 1. The host.
$hostDeploy = Join-Path $ForeverProbe "Tools\deploy.ps1"
if (-not (Test-Path -LiteralPath $hostDeploy)) {
    Write-Error "ForeverProbe checkout not found at $ForeverProbe (or set `$env:FOREVERPROBE)"; exit 1
}
& pwsh -NoProfile -File $hostDeploy -AddOnsPath $AddOnsPath
if ($LASTEXITCODE -ne 0) { Write-Error "ForeverProbe deploy refused; WowTestKitProbe was not touched"; exit 1 }

# 2. The module.
$commit = "unknown"
try {
    $commit = (git -C $RepoRoot rev-parse --short HEAD).Trim()
    if (git -C $RepoRoot status --porcelain -- tools) { $commit += " (with uncommitted changes)" }
} catch { }
$dest = Join-Path $AddOnsPath "WowTestKitProbe"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($f in $Files) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination (Join-Path $dest $f) -Force }
Get-ChildItem -LiteralPath $dest -File | Where-Object { $Files -notcontains $_.Name } | ForEach-Object {
    Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $_.FullName -Force
}
Write-Host "WowTestKitProbe $commit deployed to $dest. In game: /reload, then /fp steps tk reparent." -ForegroundColor Green
