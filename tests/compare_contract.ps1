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

# -Patch: a change to the kit runner's text, as @(from, to), for an output the parser can't read.
function New-FixtureKit([string]$Count, [string[]]$Snap, [string]$Extra = "", [switch]$NoData, [string[]]$Patch) {
    $dir = Join-Path $root ("kit-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $dir "scripts") | Out-Null
    if (-not $NoData) {
        New-Item -ItemType Directory -Path (Join-Path $dir "data/forever-70532") | Out-Null
        Set-Content -LiteralPath (Join-Path $dir "data/forever-70532/events.txt") -Value "ADDON_LOADED"
    }
    $runner = [IO.File]::ReadAllText((Join-Path $kitRepo "scripts/run.ps1"))
    if ($Patch) {
        if (!$runner.Contains($Patch[0])) { throw "The runner has no '$($Patch[0])' to patch" }
        $runner = $runner.Replace($Patch[0], $Patch[1])
    }
    [IO.File]::WriteAllText((Join-Path $dir "scripts/run.ps1"), $runner)
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

# Every run leaves no lock or backup behind, refusals included, except -Leftover:
# one that found them already there and must leave them as they were.
function Invoke-Compare([string[]]$CompareArgs, [int]$Code, [string[]]$Has, [string[]]$Lacks = @(), [switch]$Leftover) {
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
    if (-not $Leftover) {
        foreach ($f in "$pin.compare-backup", "$pin.compare-lock", "$pin.compare-backup.partial") {
            if (Test-Path -LiteralPath $f) { throw "${what}: $f was left behind" }
        }
    }
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
    $k7 = New-FixtureKit "3" "frame A" -Patch @('Write-Host "-- $($_.Name) "', 'Write-Host "== $($_.Name) "')  # no header read
    $k8 = New-FixtureKit "3" "frame A" -Patch @('"All $ran test files passed', '"Everything passed')         # no summary read
    $k9 = New-FixtureKit "3" @("frame A", "frame B")       # two snapshot lines...
    $k10 = New-FixtureKit "3" @("frame B", "frame A")      # ...swapped

    Copy-Item -LiteralPath (Join-Path $kitRepo "bootstrap/kit.ps1") -Destination (Join-Path $repo "tests/kit.ps1")
    $files = @{
        'tests/run.ps1' = @(
            'param([string]$Lua)'
            '$RepoRoot = Split-Path -Parent $PSScriptRoot'
            '. (Join-Path $PSScriptRoot "kit.ps1")'
            '$kit = Get-WowTestKit -RepoRoot $RepoRoot'
            '& (Join-Path $kit "scripts/run.ps1") -RepoRoot $RepoRoot -Lua $Lua'
            'exit $LASTEXITCODE')
        # A line of its own that looks like Lua's error, before a valid result.
        'tests/test_a.lua' = @(
            'print("lua: optional tool unavailable")'
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
        # A name with a space, as the runner's tests/test_*.lua finds it.
        'tests/test_d d.lua' = @(
            'local f = assert(io.open(os.getenv("WOWTESTKIT") .. "/count.txt"))'
            'local n = f:read("*l") f:close()'
            'if n == "crash" then n = "3" end'
            'print("test_d d: " .. n .. " passed, 0 failed")')
        # Each line of snap.txt, then whether the lock and the backup are there while it runs.
        'snapshot.lua' = @(
            'print("## named frames")'
            'for l in io.lines(os.getenv("WOWTESTKIT") .. "/snap.txt") do print(l) end'
            'local lock, backup = io.open("tests/kit.pin.compare-lock"), io.open("tests/kit.pin.compare-backup")'
            'print((lock and "lock" or "no lock") .. ", " .. (backup and "backup" or "no backup"))'
            'if lock then lock:close() end if backup then backup:close() end')
    }
    foreach ($k in $files.Keys) { Set-Content -LiteralPath (Join-Path $repo $k) -Value $files[$k] }
    Set-Pin $k1
    git -C $repo init --quiet
    git -C $repo @git add -A
    git -C $repo @git commit --quiet -m "pin k1"
    if ($LASTEXITCODE) { throw "Cannot commit the consumer" }

    # A bump to k2, compared with the pin HEAD committed: test_a's and test_d d's lines only.
    Set-Pin $k2
    $out = Invoke-Compare @('-Compare', 'HEAD', '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 1 @(
        "old pin: sha $($k1.Substring(0, 7)), build 70532, api 2 (HEAD:tests/kit.pin)",
        "new pin: sha $($k2.Substring(0, 7))",
        "test_a.lua", "  old: test_a: 3 passed, 0 failed", "  new: test_a: 4 passed, 0 failed",
        "test_d d.lua", "  old: test_d d: 3 passed, 0 failed", "  new: test_d d: 4 passed, 0 failed",
        "result lines: 2 of 4 test files identical", "load snapshot: identical (3 lines, exit 0)"
    ) @("test_b.lua", "test_c.lua", "summary", "FAILED")
    # The lock was held through both runs: each snapshot saw it.
    $logs = [regex]::Match($out, 'full outputs: (.+)').Groups[1].Value.Trim()
    foreach ($side in 'old', 'new') {
        if ((Get-Content -LiteralPath (Join-Path $logs "$side-snapshot.txt")) -notcontains "lock, backup") {
            throw "The $side run didn't see tests/kit.pin.compare-lock and .compare-backup"
        }
    }

    # The issue's form: the old kit sha. Nothing differs.
    Set-Pin $k1
    Invoke-Compare @('-Compare', $k4, '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 0 @(
        "old pin: sha $($k4.Substring(0, 7)), build 70532, api 2 (tests/kit.pin with sha=$($k4.Substring(0, 7)))",
        "result lines: 4 of 4 test files identical", "load snapshot: identical",
        "the kit at this sha has no data for build 70532"
    ) @("test_a.lua") | Out-Null

    # The hint is about the old pin only.
    Set-Pin $k4
    Invoke-Compare @('-Compare', $k1, '-Lua', $Lua) 0 @("result lines: 4 of 4 test files identical") @("has no data for build") | Out-Null
    Set-Pin $k1

    # The snapshot differs; the result lines don't.
    Invoke-Compare @('-Compare', $k3, '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 1 @(
        "result lines: 4 of 4 test files identical", "load snapshot: DIFFERS", "  from line 2:",
        "  old: frame B", "  new: frame A"
    ) @("has no data for build", "lock, backup") | Out-Null

    # Lines that only change order: shown in order, from the first that differs.
    Set-Pin $k10
    Invoke-Compare @('-Compare', $k9, '-Snapshot', 'snapshot.lua', '-Lua', $Lua) 1 @(
        "load snapshot: DIFFERS", "  from line 2:`n  old: frame A`n  old: frame B`n  new: frame B`n  new: frame A"
    ) | Out-Null
    Set-Pin $k1

    # A run whose results can't all be read is not "identical".
    Invoke-Compare @('-Compare', $k7, '-Lua', $Lua) 1 @("FAILED: old tests (read 0 of the 4 files' results)") | Out-Null
    Invoke-Compare @('-Compare', $k8, '-Lua', $Lua) 1 @("FAILED: old tests (no runner summary in the output)") | Out-Null

    # A test file Lua stopped: its error, not its traceback's last line; the summary differs.
    Invoke-Compare @('-Compare', $k5, '-Lua', $Lua) 1 @(
        "test_a.lua", "  old: error: ", "test_a.lua:4: crash", "  new: test_a: 3 passed, 0 failed",
        "summary", "  old: 1 of 4 test file(s) FAILED (exit 1)", "  new: All 4 test files passed (1 skipped). (exit 0)",
        "result lines: 3 of 4 test files identical"
    ) @("[C]: ?", "optional tool unavailable") | Out-Null

    # Both runs fail the same way: identical, and still not a pass.
    Set-Pin $k6
    Invoke-Compare @('-Compare', $k5, '-Lua', $Lua) 1 @(
        "result lines: 4 of 4 test files identical", "FAILED: old tests (exit 1), new tests (exit 1)."
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

    # What an earlier -Compare left: the refusal says whether it runs and what to
    # do, and touches nothing. A lock names its process; this one's id with
    # another start time is a process that stopped.
    $lockFile, $backupFile = "$pin.compare-lock", "$pin.compare-backup"
    $live = "pid=$PID start=$((Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)`n"
    $dead = "pid=$PID start=0`n"
    $asIs = [IO.File]::ReadAllText($pin)
    $running = "Another -Compare is running in this repo (process $PID): wait for it to finish"
    $before = "is no longer running: it stopped before it changed tests\kit.pin. Then delete"
    $move = "it stopped with its old pin in tests\kit.pin, and "
    foreach ($c in @(
        @{ Lock = $live; Backup = $null;       Has = $running }
        @{ Lock = $live; Backup = "sha=$k2`n"; Has = $running }   # its old pin is in: wait, don't move
        @{ Lock = $dead; Backup = $null;       Has = $before }
        @{ Lock = "";    Backup = $null;       Has = $before }    # stopped before it wrote its process
        @{ Lock = $dead; Backup = $asIs;       Has = "is no longer running: tests\kit.pin is as it was: delete " }
        @{ Lock = $dead; Backup = "sha=$k2`n"; Has = "is no longer running: $move" }
        @{ Lock = $null; Backup = "sha=$k2`n"; Has = "is left from an earlier -Compare: $move" }
    )) {
        foreach ($f in @{ $lockFile = $c.Lock; $backupFile = $c.Backup }.GetEnumerator()) {
            if ($null -ne $f.Value) { [IO.File]::WriteAllText($f.Key, $f.Value) }
        }
        $lacks = if ($c.Has -ceq $running) { "move it over" } else { "wait for it" }
        Invoke-Compare @('-Compare', $k2, '-Lua', $Lua) 2 @($c.Has) @($lacks) -Leftover | Out-Null
        foreach ($f in @{ $lockFile = $c.Lock; $backupFile = $c.Backup }.GetEnumerator()) {
            $now = if (Test-Path -LiteralPath $f.Key) { [IO.File]::ReadAllText($f.Key) }
            if ($now -cne $f.Value) { throw "A refusal changed $($f.Key): '$now', was '$($f.Value)'" }
            if ($null -ne $f.Value) { Remove-Item -LiteralPath $f.Key }
        }
    }
    # A lock still empty because its owner is writing it (opened by kit.ps1's
    # own New-WowTestKitLock): running, not stopped. Closed and empty is above.
    . (Join-Path $repo "tests/kit.ps1")
    $held = New-WowTestKitLock $lockFile
    try {
        Invoke-Compare @('-Compare', $k2, '-Lua', $Lua) 2 @("Another -Compare is running in this repo: wait for it to finish") @("delete") -Leftover | Out-Null
    } finally { $held.Dispose() }
    if ((Get-Item -LiteralPath $lockFile).Length -ne 0 -or (Test-Path -LiteralPath $backupFile)) { throw "A refusal changed a lock being written" }
    Remove-Item -LiteralPath $lockFile

    Write-Host "kit.ps1 -Compare: both forms, the snapshot, the refusals; tests/kit.pin put back each time."
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    $resolved = (Resolve-Path -LiteralPath $root -ErrorAction SilentlyContinue).Path
    if ($resolved -eq $root -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
exit 0
