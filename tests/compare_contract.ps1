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
# -Edit: what the snapshot script writes into tests/kit.pin when run against this kit.
function New-FixtureKit([string]$Count, [string[]]$Snap, [string]$Extra = "", [switch]$NoData, [string[]]$Patch, [string]$Edit = "") {
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
    if ($Edit) { [IO.File]::WriteAllText((Join-Path $dir "edit.txt"), $Edit) }
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
    $k11 = New-FixtureKit "3" "frame A" -Edit "sha=edited meanwhile`n"   # its snapshot edits the pin
    $k12 = New-FixtureKit "3" "frame A" -Edit "sha=$k1`n# the pin`nbuild=70532`napi=2`n"   # ...to -Compare <k1>'s old pin
    $k13 = New-FixtureKit "3" "frame A" -Edit "# the pin`r`nsha=$k1 # pinned kit`r`nbuild=70532`r`napi=2`r`n"   # ...back to Set-Pin $k1

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
            'if lock then lock:close() end if backup then backup:close() end'
            # An edit to the pin while the comparison runs (the kit's edit.txt).
            'local e = io.open(os.getenv("WOWTESTKIT") .. "/edit.txt", "rb")'
            'if e then local t = e:read("*a") e:close() local p = assert(io.open("tests/kit.pin", "wb")) p:write(t) p:close() end')
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
    if ((Split-Path -Leaf $logs) -cnotmatch '^WowTestKit-compare-[0-9]{8}-[0-9]{6}-[0-9]+$') { throw "The logs aren't in a folder of their own: $logs" }
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

    # An edit to tests/kit.pin while -Compare runs (#121): kept, the pin as it
    # was saved in the logs, nothing left behind, and exit 2. Edits to exactly
    # the old pin's bytes too: only the pin this run wrote is its to put back.
    # Direct: kit.ps1 run as a consumer runs it, a fixture kit's snapshot
    # script editing the pin during that kit's side. Hooked: Compare-WowTestKit
    # dot-sourced, with a git or Write-Host function that edits the pin while
    # git reads HEAD's pin (before the old pin goes in) or while the results
    # are printed (after the last run).
    $hooked = Join-Path $root "edit-hooked.ps1"
    Set-Content -LiteralPath $hooked -Value @(
        'param($Repo, $Lua, $Compare, $Mode)'
        '. (Join-Path $Repo "tests/kit.ps1")'
        '$pinFile = Join-Path $Repo "tests/kit.pin"'
        '$realGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source'
        'function git {'
        '    $r = & $realGit @args'
        '    if ($Mode -eq "git-edit" -and $args -contains "show") { [IO.File]::WriteAllText($pinFile, "sha=edited meanwhile`n") }'
        '    if ($Mode -eq "git-old" -and $args -contains "show") { [IO.File]::WriteAllText($pinFile, (($r -join "`n") + "`n")) }'
        '    $r'
        '}'
        'function Write-Host {'
        '    if ($Mode -eq "print" -and "$args" -like "result lines:*") { [IO.File]::WriteAllText($pinFile, "sha=edited meanwhile`n") }'
        '    Microsoft.PowerShell.Utility\Write-Host @args'
        '}'
        'exit (Compare-WowTestKit -Compare $Compare -Lua $Lua -RepoRoot $Repo)')
    $edited = "sha=edited meanwhile`n"
    $headPin = "# the pin`nsha=$k1 # pinned kit`nbuild=70532`napi=2`n"   # HEAD's, as -Compare HEAD writes it
    $kitOld = "sha=$k1`n# the pin`nbuild=70532`napi=2`n"                 # -Compare <k1> over this pin
    foreach ($c in @(
        @{ What = "during the old run"; Pin = $k1; Old = $k11; Edit = $edited; Ran = @("-- old pin"); NotRan = @("-- new pin", "result lines") }
        @{ What = "during the new run"; Pin = $k11; Old = $k1; Edit = $edited; Ran = @("-- old pin", "-- new pin"); NotRan = @("result lines") }
        @{ What = "to the old pin, during the new run"; Pin = $k12; Old = $k1; Edit = $kitOld; Ran = @("-- new pin"); NotRan = @("result lines") }
        # A git restore of the startup pin during the old run: the old run may have read it.
        @{ What = "back to the startup pin, during the old run"; Pin = $k1; Old = $k13; Edit = "# the pin`r`nsha=$k1 # pinned kit`r`nbuild=70532`r`napi=2`r`n"; Ran = @("-- old pin"); NotRan = @("-- new pin", "result lines") }
        @{ What = "before the old pin goes in"; Pin = $k2; Old = "HEAD"; Mode = "git-edit"; Edit = $edited; Ran = @(); NotRan = @("-- old pin") }
        @{ What = "to the old pin, before it goes in"; Pin = $k2; Old = "HEAD"; Mode = "git-old"; Edit = $headPin; Ran = @(); NotRan = @("-- old pin") }
        @{ What = "after the last run"; Pin = $k1; Old = $k4; Mode = "print"; Edit = $edited; Ran = @("-- new pin", "result lines: 4 of 4 test files identical"); NotRan = @() }
    )) {
        Set-Pin $c.Pin
        $was = [IO.File]::ReadAllBytes($pin)
        if ($c.Mode) {
            $out = (& $pwsh -NoProfile -File $hooked -Repo $repo -Lua $Lua -Compare $c.Old -Mode $c.Mode 2>&1) -join "`n"; $got = $LASTEXITCODE
        } else {
            Push-Location $repo
            try { $out = (& $pwsh -NoProfile -File (Join-Path $repo "tests/kit.ps1") -Compare $c.Old -Snapshot snapshot.lua -Lua $Lua 2>&1) -join "`n"; $got = $LASTEXITCODE }
            finally { Pop-Location }
        }
        $what = "an edit $($c.What)"
        if ($got -ne 2) { throw "${what}: exit $got, expected 2. Output:`n$out" }
        foreach ($s in @("tests\kit.pin was changed while -Compare ran: it is left as it is, and the comparison stopped.") + $c.Ran) {
            if (!$out.Contains($s)) { throw "${what}: no '$s' in:`n$out" }
        }
        foreach ($s in $c.NotRan + @("could not be put back")) { if ($out.Contains($s)) { throw "${what}: '$s' should not be in:`n$out" } }
        if ([IO.File]::ReadAllText($pin) -cne $c.Edit) { throw "${what}: the edit was not kept: '$([IO.File]::ReadAllText($pin))'" }
        $savedPin = [regex]::Match($out, 'as it was before is in (.+)').Groups[1].Value.Trim()
        if (-not $savedPin -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($savedPin)) -cne [Convert]::ToBase64String($was)) {
            throw "${what}: the pin as it was isn't in '$savedPin'"
        }
        foreach ($f in "$pin.compare-backup", "$pin.compare-lock", "$pin.compare-backup.partial") {
            if (Test-Path -LiteralPath $f) { throw "${what}: $f was left behind" }
        }
    }
    Set-Pin $k1

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
        # Naming no process: nothing to check, so no "it stopped", only what to do once sure.
        @{ Lock = "";        Backup = $null;       Has = "names no process to check. Make sure no -Compare is running in this repo; if none is, it stopped before it changed"; Lacks = "is no longer running" }
        @{ Lock = "garbage"; Backup = "sha=$k2`n"; Has = "names no process to check. Make sure no -Compare is running in this repo; if none is, $move"; Lacks = "is no longer running" }
        @{ Lock = $dead; Backup = $asIs;       Has = "is no longer running: tests\kit.pin is as it was: delete " }
        @{ Lock = $dead; Backup = "sha=$k2`n"; Has = "is no longer running: $move" }
        @{ Lock = $null; Backup = "sha=$k2`n"; Has = "is left from an earlier -Compare: $move" }
    )) {
        foreach ($f in @{ $lockFile = $c.Lock; $backupFile = $c.Backup }.GetEnumerator()) {
            if ($null -ne $f.Value) { [IO.File]::WriteAllText($f.Key, $f.Value) }
        }
        $lacks = @(if ($c.Has -ceq $running) { "move it over" } else { "wait for it" }) + @($c.Lacks | Where-Object { $_ })
        Invoke-Compare @('-Compare', $k2, '-Lua', $Lua) 2 @($c.Has) $lacks -Leftover | Out-Null
        foreach ($f in @{ $lockFile = $c.Lock; $backupFile = $c.Backup }.GetEnumerator()) {
            $now = if (Test-Path -LiteralPath $f.Key) { [IO.File]::ReadAllText($f.Key) }
            if ($now -cne $f.Value) { throw "A refusal changed $($f.Key): '$now', was '$($f.Value)'" }
            if ($null -ne $f.Value) { Remove-Item -LiteralPath $f.Key }
        }
    }
    # kit.ps1's own New-WowTestKitLock creates the lock with its content and
    # refuses an existing one without touching it.
    . (Join-Path $repo "tests/kit.ps1")
    $content = [Text.Encoding]::ASCII.GetBytes("pid=1 start=2`n")
    $other = [Text.Encoding]::ASCII.GetBytes("pid=3 start=4`n")
    if ((New-WowTestKitLock $lockFile $content) -ne $true) { throw "New-WowTestKitLock didn't make a new lock" }
    if ((New-WowTestKitLock $lockFile $other) -ne $false) { throw "New-WowTestKitLock took an existing lock" }
    if ([IO.File]::ReadAllText($lockFile) -cne "pid=1 start=2`n") { throw "New-WowTestKitLock changed an existing lock" }
    Remove-Item -LiteralPath $lockFile
    # Switch-WowTestKitPin: replaces only the bytes it expects, and not while
    # another handle has the pin open, so a writer can't slip in between its
    # check and its write (#121).
    $a, $b = [Text.Encoding]::ASCII.GetBytes("sha=a`n"), [Text.Encoding]::ASCII.GetBytes("sha=b`n")
    [IO.File]::WriteAllBytes($pin, $a)
    if ((Switch-WowTestKitPin $pin $b $a) -ne $false -or [IO.File]::ReadAllText($pin) -cne "sha=a`n") { throw "Switch-WowTestKitPin replaced bytes it didn't expect" }
    if ((Switch-WowTestKitPin $pin $a $b) -ne $true -or [IO.File]::ReadAllText($pin) -cne "sha=b`n") { throw "Switch-WowTestKitPin didn't replace the bytes it expected" }
    $held = [IO.File]::Open($pin, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    try {
        $refused = try { $null = Switch-WowTestKitPin $pin $b $a; $false } catch [IO.IOException] { $true }
        if (-not $refused) { throw "Switch-WowTestKitPin wrote while another handle had the pin open" }
    } finally { $held.Dispose() }
    if ([IO.File]::ReadAllText($pin) -cne "sha=b`n") { throw "Switch-WowTestKitPin changed a pin held open" }
    if ((Switch-WowTestKitPin (Join-Path $root "no-such-pin") $a $b) -ne $false) { throw "Switch-WowTestKitPin: a missing pin isn't `$false" }
    Set-Pin $k1
    # Two comparisons started in the same second get their own log folders (#121).
    $logRoot = Join-Path $root "logs"
    New-Item -ItemType Directory -Path $logRoot | Out-Null
    $d1 = New-WowTestKitLogDir -Stamp "20260101-000000" -Root $logRoot
    $d2 = New-WowTestKitLogDir -Stamp "20260101-000000" -Root $logRoot
    if ($d1 -eq $d2) { throw "New-WowTestKitLogDir gave one folder twice: $d1" }
    foreach ($d in $d1, $d2) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "New-WowTestKitLogDir didn't create $d" }
        if ((Split-Path -Leaf $d) -cnotlike "WowTestKit-compare-20260101-000000-$PID*") { throw "Log folder not named by time and process: $d" }
    }
    if (@(Get-ChildItem -LiteralPath $logRoot).Count -ne 2) { throw "Expected two log folders in $logRoot" }

    Write-Host "kit.ps1 -Compare: both forms, the snapshot, the refusals; tests/kit.pin put back each time."
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    $resolved = (Resolve-Path -LiteralPath $root -ErrorAction SilentlyContinue).Path
    if ($resolved -eq $root -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
exit 0
