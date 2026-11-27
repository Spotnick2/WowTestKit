<#
    scripts/run.ps1 - Syntax-check a repo's Lua files and run every
    tests\test_*.lua in it under Lua 5.1, one process per file. A consumer's
    tests\run.ps1 calls it after Get-WowTestKit (bootstrap/kit.ps1).

    -Toc: the TOC whose .lua files are syntax-checked (the TOC is the list, so a
    new file cannot go unchecked); -Extra: more files to check (plugins, probes).
    Each test file's own "<name>: N passed, M failed" or "SKIPPED" line is
    printed; skips are counted in the summary, never hidden.
#>

param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$Toc,
    [string[]]$Extra = @(),
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) { Write-Error "Lua 5.1 not found at $Lua (pass -Lua <path>)"; exit 1 }
$KitRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    $files = @()
    if ($Toc) {
        $files += Get-Content -LiteralPath $Toc | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" }
    }
    $files += $Extra
    if ($files.Count -gt 0) {
        if (-not (Test-Path $luac)) {
            Write-Host "luac -p SKIPPED: no luac.exe beside $Lua - syntax was NOT checked" -ForegroundColor Yellow
        } else {
            & $luac -p @files
            if ($LASTEXITCODE -ne 0) { Write-Host "luac -p FAILED" -ForegroundColor Red; exit 1 }
            Remove-Item -LiteralPath "luac.out" -ErrorAction SilentlyContinue
            Write-Host "luac -p: ok ($($files.Count) files)" -ForegroundColor DarkGray
        }
    }

    # A newer build than the pin's: the workspace rule is to test the newest.
    $pinFile = if ($env:WOWTESTKIT_PIN) { $env:WOWTESTKIT_PIN } else { "tests\kit.pin" }   # kit.ps1 -Compare's fixed pin
    $pinBuild = (Get-Content -LiteralPath $pinFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*build\s*=\s*(\d+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $newest = Get-ChildItem (Join-Path $KitRoot "data") -Directory -Filter "forever-*" -ErrorAction SilentlyContinue |
        ForEach-Object { [int]($_.Name -replace '^forever-', '') } | Sort-Object | Select-Object -Last 1
    if ($pinBuild -and $newest -and $newest -gt [int]$pinBuild) {
        Write-Host "note: the kit has data for build $newest; tests\kit.pin selects $pinBuild" -ForegroundColor Yellow
    }

    $failed, $skipped, $ran = 0, 0, 0
    Get-ChildItem -File "tests/test_*.lua" | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        $out = @(& $Lua $_.FullName 2>&1)
        $code = $LASTEXITCODE
        $out | ForEach-Object { Write-Host $_ }
        # The result is the last line that isn't blank, as in run.sh.
        $last = [string]($out | Where-Object { "$_".Trim() -ne '' } | Select-Object -Last 1)
        $ran++
        if ($code -ne 0) { $failed++ }
        elseif ($last -cmatch '^(.+: SKIPPED \(.+\)|SKIPPED: .+)$') { $skipped++ }
        elseif ($last -cnotmatch '^.+: [0-9]+ passed, 0 failed$') {
            Write-Host "$($_.Name): missing successful final test result" -ForegroundColor Red
            $failed++
        }
    }
    if ($ran -eq 0) { Write-Host "No tests/test_*.lua files found" -ForegroundColor Red; exit 1 }
    if ($failed -gt 0) { Write-Host "$failed of $ran test file(s) FAILED" -ForegroundColor Red; exit 1 }
    $note = if ($skipped -gt 0) { " ($skipped skipped)" } else { "" }
    Write-Host "All $ran test files passed$note." -ForegroundColor Green
    exit 0
}
finally { Pop-Location }
