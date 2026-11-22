<#
    tests/kit.ps1: puts WowTestKit at the commit tests/kit.pin names into the
    local cache and returns its folder. Dot-source it from tests/run.ps1.
    Copied from WowTestKit's bootstrap/kit.ps1: never edit a consumer's copy;
    change the kit's and copy it again.

    The cache is %LOCALAPPDATA%\WowTestKit\<sha>, outside the repo. A valid
    cache (HEAD is the pin) is used as it is, offline too; otherwise it is
    fetched (git, depth 1) and checked to BE the pinned commit.
    -KitDev uses the sibling ..\WowTestKit working copy instead (or
    $env:WOWTESTKIT_DEV), and says so: for testing a kit change.
#>

function Get-WowTestKit {
    param([Parameter(Mandatory)][string]$RepoRoot, [switch]$KitDev)

    $pin = @{}
    Get-Content (Join-Path $RepoRoot "tests\kit.pin") | ForEach-Object {
        $line = $_ -replace '\s+#.*$', ''
        if ($line -match '^\s*(\w+)\s*=\s*(.*?)\s*$') { $pin[$Matches[1]] = $Matches[2] }
    }
    if (-not $pin.sha -or -not $pin.build) { throw "tests\kit.pin needs sha= and build=" }
    if ($pin.sha -cnotmatch '^[0-9a-f]{40}$') { throw "tests\kit.pin needs a 40-hex sha=" }

    if ($KitDev) {
        $dir = if ($env:WOWTESTKIT_DEV) { $env:WOWTESTKIT_DEV } else { Join-Path (Split-Path -Parent $RepoRoot) "WowTestKit" }
        if (-not (Test-Path (Join-Path $dir "kit.lua"))) { throw "-KitDev: no WowTestKit working copy at $dir" }
        Write-Host "WowTestKit: DEV working copy $dir, NOT the pin $($pin.sha.Substring(0, 7))" -ForegroundColor Yellow
    } else {
        $cacheRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "WowTestKit"))
        $dir = [IO.Path]::GetFullPath((Join-Path $cacheRoot $pin.sha))
        if ([IO.Path]::GetDirectoryName($dir) -ne $cacheRoot) { throw "Invalid WowTestKit cache path: $dir" }
        foreach ($path in $cacheRoot, $dir) {
            $item = Get-Item -Force -LiteralPath $path -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing a linked WowTestKit cache path: $path"
            }
        }
        $head = $null
        if (Test-Path (Join-Path $dir ".git")) { $head = (git -C $dir rev-parse HEAD 2>$null) }
        if ($head -ne $pin.sha) {
            # Only this cache folder, named after the pin, is ever replaced.
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop }
            New-Item -ItemType Directory -Force $dir | Out-Null
            git -C $dir init --quiet
            git -C $dir fetch --quiet --depth 1 https://github.com/Spotnick2/WowTestKit.git $pin.sha
            if ($LASTEXITCODE -ne 0) { throw "could not fetch WowTestKit $($pin.sha) (offline, or not pushed?)" }
            git -C $dir checkout --quiet FETCH_HEAD
            $head = (git -C $dir rev-parse HEAD)
            if ($head -ne $pin.sha) { throw "WowTestKit at $dir is $head, not the pin $($pin.sha)" }
        }
        Write-Host "WowTestKit: $($pin.sha.Substring(0, 7)), build $($pin.build)" -ForegroundColor DarkGray
    }
    $env:WOWTESTKIT = $dir
    return $dir
}
