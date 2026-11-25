# bootstrap/kit.ps1 -Compare (#118), end to end and offline: a disposable
# consumer, four fixture kit commits in an isolated cache, each with the real
# scripts/run.ps1. Each fixture kit says how many checks test_a passes
# (count.txt) and what the snapshot script prints (snap.txt).
# -Lua: a Lua 5.1 interpreter (lua5.1 in CI, the full path on Windows).
param([string]$Lua = "lua5.1")
$ErrorActionPreference = "Stop"
$Lua = (Get-Command $Lua -CommandType Application | Select-Object -First 1).Source
$kitRepo = Split-Path -Parent $PSScriptRoot
$pwsh = (Get-Process -Id $PID).Path
$tempRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName.TrimEnd('\', '/')
$root = Join-Path $tempRoot ("wowtestkit-compare-" + [guid]::NewGuid())
$repo = Join-Path $root "consumer"
$cache = Join-Path $root "WowTestKit"
$pin = Join-Path $repo "tests/kit.pin"
$saved = @{}
foreach ($k in 'LOCALAPPDATA', 'WOWTESTKIT', 'GIT_ALLOW_PROTOCOL', 'TEMP', 'TMP', 'TMPDIR') {
    $saved[$k] = [Environment]::GetEnvironmentVariable($k)
}
$git = @('-c', 'core.autocrlf=false', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false')

function New-FixtureKit([string]$Count, [string]$Snap, [string]$Extra = "", [switch]$NoData) {
    $dir = Join-Path $root ("kit-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $dir "scripts") | Out-Null
    if (-not $NoData) {
        New-Item -ItemType Directory -Path (Join-Path $dir "data/forever-70532") | Out-Null
        Set-Content -LiteralPath (Join-Path $dir "data/forever-70532/events.txt") -Value "ADDON_LOADED"
    }
    Copy-Item -LiteralPath (Join-Path $kitRepo "scripts/run.ps1") -Destination (Join-Path $dir "scripts/run.ps1")
    Set-Content -LiteralPath (Join-Path $dir "count.txt") -Value $Count
    Set-Content -LiteralPath (Join-Path $dir "snap.txt") -Value $Snap
    if ($Extra) { Set-Content -LiteralPath (Join-Path $dir "extra.txt") -Value $Extra }
    git -C $dir init --quiet
    git -C $dir @git add -A
    git -C $dir @git commit --quiet -m fixture
    if ($LASTEXITCODE) { throw "Cannot commit a fixture kit" }
    $sha = git -C $dir rev-parse HEAD
    Move-Item -LiteralPath $dir -Destination (Join-Path $cache $sha)
    return $sha
}

# The consumer's pin, CRLF and with a comment, so "put back byte for byte" is tested.
function Set-Pin([string]$Sha) {
    [IO.File]::WriteAllText($pin, "# the pin`r`nsha=$Sha # pinned kit`r`nbuild=70532`r`napi=2`r`n")
}

function Invoke-Compare([string[]]$CompareArgs, [int]$Code, [string[]]$Has, [string[]]$Lacks = @()) {
    $before = [IO.File]::ReadAllBytes($pin)
    Push-Location $repo
    try { $out = (& $pwsh -NoProfile -File (Join-Path $repo "tests/kit.ps1") @CompareArgs 2>&1) -join "`n"; $got = $LASTEXITCODE }
    finally { Pop-Location }
    $what = "-Compare $($CompareArgs -join ' ')"
    if ($got -ne $Code) { throw "${what}: exit $got, expected $Code. Output:`n$out" }
    foreach ($s in $Has) { if (!$out.Contains($s)) { throw "${what}: no '$s' in:`n$out" } }
    foreach ($s in $Lacks) { if ($out.Contains($s)) { throw "${what}: '$s' should not be in:`n$out" } }
    $after = [IO.File]::ReadAllBytes($pin)
    if ([Convert]::ToBase64String($after) -cne [Convert]::ToBase64String($before)) { throw "${what}: tests/kit.pin changed" }
    if ((Test-Path -LiteralPath "$pin.compare-backup") -and $Code -ne 2) { throw "${what}: the backup was left behind" }
    return $out
}

try {
    New-Item -ItemType Directory -Path $cache, (Join-Path $repo "tests") | Out-Null
    $env:LOCALAPPDATA = $root
    $env:GIT_ALLOW_PROTOCOL = 'file'   # a fetch from GitHub fails: only the cache is used
    $env:TEMP = $env:TMP = $env:TMPDIR = $root   # the comparisons' logs go with the rest
    $k1 = New-FixtureKit "3" "frame A"
    $k2 = New-FixtureKit "4" "frame A"                     # test_a's count differs
    $k3 = New-FixtureKit "3" "frame B"                     # the snapshot differs
    $k4 = New-FixtureKit "3" "frame A" "nothing else" -NoData   # nothing differs; no data for the pin's build
    $k5 = New-FixtureKit "crash" "frame A"                 # test_a stops with an error
    $k6 = New-FixtureKit "crash" "frame A" "same crash"    # the same failing run

    Copy-Item -LiteralPath (Join-Path $kitRepo "bootstrap/kit.ps1") -Destination (Join-Path $repo "tests/kit.ps1")
    $files = @{
        'tests/run.ps1' = @(
            'param([string]$Lua)'
            '$RepoRoot = Split-Path -Parent $PSScriptRoot'
            '. (Join-Path $PSScriptRoot "kit.ps1")'
            '$kit = Get-WowTestKit -RepoRoot $RepoRoot'
            '& (Join-Path $kit "scripts/run.ps1") -RepoRoot $RepoRoot -Lua $Lua'
            'exit $LASTEXITCODE')
        'tests/test_a.lua' = @(
            'local f = assert(io.open(os.getenv("WOWTESTKIT") .. "/count.txt"))'
            'local n = f:read("*l") f:close()'
            'if n == "crash" then error("crash") end'
            'print("test_a: " .. n .. " passed, 0 failed")')
        # Its first line follows the kit, its result doesn't: only the result counts.
        'tests/test_b.lua' = @(
            'local f = assert(io.open(os.getenv("WOWTESTKIT") .. "/snap.txt"))'
            'print("drew " .. f:read("*l")) f:close()'
            'print("test_b: 2 passed, 0 failed")')
        'tests/test_c.lua' = @('print("SKIPPED: optional")')
        'snapshot.lua' = @(
            'local f = assert(io.open(os.getenv("WOWTESTKIT") .. "/snap.txt"))'
            'print("## named frames") print(f:read("*l")) f:close()')
    }
    foreach ($k in $files.Keys) { Set-Content -LiteralPath (Join-Path $repo $k) -Value $files[$k] }
    Set-Pin $k1
    git -C $repo init --quiet
    git -C $repo @git add -A
    git -C $repo @git commit --quiet -m "pin k1"
    if ($LASTEXITCODE) { throw "Cannot commit the consumer" }

    # A bump to k2, compared with the pin HEAD committed: test_a's line only.
    Set-Pin $k2
    $out = Invoke-Compare @('-Compare', 'HEAD', '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 1 @(
        "old pin: sha $($k1.Substring(0, 7)), build 70532, api 2 (HEAD:tests/kit.pin)",
        "new pin: sha $($k2.Substring(0, 7))",
        "test_a.lua", "  old: test_a: 3 passed, 0 failed", "  new: test_a: 4 passed, 0 failed",
        "result lines: 2 of 3 test files identical", "load snapshot: identical (2 lines, exit 0)"
    ) @("test_b.lua", "test_c.lua", "summary")

    # The issue's form: the old kit sha. Nothing differs.
    Set-Pin $k1
    Invoke-Compare @('-Compare', $k4, '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 0 @(
        "old pin: sha $($k4.Substring(0, 7)), build 70532, api 2 (tests/kit.pin with sha=$($k4.Substring(0, 7)))",
        "result lines: 3 of 3 test files identical", "load snapshot: identical",
        "the kit at this sha has no data for build 70532"
    ) @("test_a.lua") | Out-Null

    # The hint is about the old pin only.
    Set-Pin $k4
    Invoke-Compare @('-Compare', $k1, '-Lua', $Lua) 0 @("result lines: 3 of 3 test files identical") @("has no data for build") | Out-Null
    Set-Pin $k1

    # The snapshot differs; the result lines don't.
    Invoke-Compare @('-Compare', $k3, '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 1 @(
        "result lines: 3 of 3 test files identical", "load snapshot: DIFFERS", "  old: frame B", "  new: frame A"
    ) @("has no data for build") | Out-Null

    # A test file Lua stopped: its error, not its traceback's last line; the summary differs.
    Invoke-Compare @('-Compare', $k5, '-Lua', $Lua) 1 @(
        "test_a.lua", "  old: error: ", "test_a.lua:3: crash", "  new: test_a: 3 passed, 0 failed",
        "summary", "  old: 1 of 3 test file(s) FAILED (exit 1)", "  new: All 3 test files passed (1 skipped). (exit 0)",
        "result lines: 2 of 3 test files identical"
    ) @("[C]: ?") | Out-Null

    # Both runs fail the same way: identical, and still not a pass.
    Set-Pin $k6
    Invoke-Compare @('-Compare', $k5, '-Lua', $Lua) 1 @(
        "result lines: 3 of 3 test files identical", "FAILED: old tests (exit 1), new tests (exit 1)."
    ) | Out-Null
    Set-Pin $k1

    # No snapshot script: said, not hidden.
    Invoke-Compare @('-Compare', $k4, '-Lua', $Lua) 0 @("load snapshot: not compared") | Out-Null

    # The old pin can't be fetched: the pin is put back, the backup removed.
    Invoke-Compare @('-Compare', ('0' * 40), '-Lua', $Lua) 2 @("could not fetch WowTestKit") | Out-Null
    if (Test-Path -LiteralPath "$pin.compare-backup") { throw "A failed old run left the backup" }

    # Refusals.
    Invoke-Compare @('-Compare', $k1, '-Lua', $Lua) 2 @("The two pins are the same") | Out-Null
    Invoke-Compare @('-Compare', 'no-such-ref', '-Lua', $Lua) 2 @("is neither") | Out-Null
    Invoke-Compare @() 2 @("usage:") | Out-Null
    [IO.File]::WriteAllText("$pin.compare-backup", "sha=$k2`n")
    Invoke-Compare @('-Compare', $k2, '-Lua', $Lua) 2 @("an earlier -Compare stopped") | Out-Null
    if ([IO.File]::ReadAllText("$pin.compare-backup") -ne "sha=$k2`n") { throw "The leftover backup was touched" }

    Write-Host "kit.ps1 -Compare: both forms, the snapshot, the refusals; tests/kit.pin put back each time."
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    $resolved = (Resolve-Path -LiteralPath $root -ErrorAction SilentlyContinue).Path
    if ($resolved -eq $root -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
exit 0
