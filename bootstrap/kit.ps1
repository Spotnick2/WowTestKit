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

    Run directly, it compares two pins (a pin bump, WowTestKit's
    docs/ADOPTING.md section 3):

        pwsh tests/kit.ps1 -Compare HEAD                 # the pin HEAD committed
        pwsh tests/kit.ps1 -Compare <old kit sha>        # this pin, another sha=
        pwsh tests/kit.ps1 -Compare main -Snapshot <script.lua> [-Lua <lua.exe>]

    It runs tests/run.ps1 with the old pin, then with tests/kit.pin as it is,
    and prints the test files whose result line differs, then whether the load
    snapshot (the -Snapshot script's output) is identical. -Compare <commit of
    this repo> takes that commit's whole tests/kit.pin (sha, build, api); a
    40-hex sha that is no commit here replaces only sha=. The old pin is
    written into tests/kit.pin for its run and the file is put back byte for
    byte after it; tests/kit.pin.compare-backup holds it meanwhile, and a
    -Compare refuses to start while that file exists. Each side's full output
    is kept in a WowTestKit-compare-<time> folder in %TEMP%. Exit 0: nothing
    differs and every run passed; 1: something differs, or a run failed (its
    identical lines prove nothing); 2: the comparison could not run.
#>

# A pin's name=value pairs. A trailing " # comment" is dropped; the last line
# for a name counts.
function ConvertFrom-WowTestKitPin {
    param([string[]]$Lines)
    $pin = @{}
    $Lines | ForEach-Object {
        $line = $_ -replace '\s+#.*$', ''
        if ($line -match '^\s*(\w+)\s*=\s*(.*?)\s*$') { $pin[$Matches[1]] = $Matches[2] }
    }
    return $pin
}

function Get-WowTestKit {
    param([Parameter(Mandatory)][string]$RepoRoot, [switch]$KitDev)

    $pin = ConvertFrom-WowTestKitPin (Get-Content (Join-Path $RepoRoot "tests\kit.pin"))
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

# Each test file's result line in the kit runner's output (scripts/run.ps1):
# "-- test_x.lua " opens a file's output, and the runner's summary closes the
# last one. The result is the file's last non-blank line, as the runner reads
# it, or "error: <message>" for a file Lua stopped with an error (its last
# line is the traceback's). Returns @{ Files = ordered name -> line; Summary = line }.
function Get-WowTestKitResults {
    param([string[]]$Lines)
    $errorRx = '^(.*[\\/])?lua(5\.1)?(\.exe)?: (.+)$'
    $summaryRx = '^(All [0-9]+ test files passed|[0-9]+ of [0-9]+ test file\(s\) FAILED|No tests/test_\*\.lua files found)'
    $files = [ordered]@{}
    $summary = $null
    $file = $null
    $body = [Collections.Generic.List[string]]::new()
    $close = {
        if (-not $file) { return }
        $e = $body | Where-Object { $_ -cmatch $errorRx } | Select-Object -First 1
        $r = if ($e) { "error: " + ($e -creplace $errorRx, '$4') } else { $body | Where-Object { $_.Trim() } | Select-Object -Last 1 }
        $files[$file] = if ($r) { $r.Trim() } else { "(no output)" }
    }
    foreach ($line in $Lines) {
        # A file that printed nothing leaves the next "-- test_y.lua " on its line.
        while ($line -cmatch '^-- (test_\S+\.lua) ?(.*)$') {
            $next, $line = $Matches[1], $Matches[2]   # before $close's own -cmatch resets $Matches
            . $close
            $file = $next
            $body.Clear()
        }
        if ($line -cmatch $summaryRx) { . $close; $file = $null; $summary = $line.Trim(); continue }
        if ($file) { $body.Add($line) }
    }
    . $close
    return @{ Files = $files; Summary = $summary }
}

function Compare-WowTestKit {
    param(
        [Parameter(Mandatory)][string]$Compare,
        [string]$Snapshot,
        [string]$Lua,
        [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
    )
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    # Forward slashes: [IO.File] doesn't read "\" as a separator off Windows.
    $pinPath = Join-Path $RepoRoot "tests/kit.pin"
    $backup = "$pinPath.compare-backup"
    $runPs1 = Join-Path $RepoRoot "tests/run.ps1"
    if (Test-Path -LiteralPath $backup) {
        Write-Host "$backup exists: an earlier -Compare stopped before putting tests\kit.pin back. Check which pin it holds, move it back over tests\kit.pin, then run again." -ForegroundColor Red
        return 2
    }
    if (-not (Test-Path -LiteralPath $runPs1)) { Write-Host "no tests\run.ps1 in $RepoRoot" -ForegroundColor Red; return 2 }
    $luaExe = if ($Lua) { $Lua } else { "C:\Program Files (x86)\Lua\5.1\lua.exe" }
    if ($Snapshot) {
        $Snapshot = (Resolve-Path -LiteralPath $Snapshot -ErrorAction SilentlyContinue).Path
        if (-not $Snapshot) { Write-Host "-Snapshot: no such file" -ForegroundColor Red; return 2 }
        if (-not (Get-Command $luaExe -ErrorAction SilentlyContinue)) { Write-Host "Lua 5.1 not found at $luaExe (pass -Lua <path>)" -ForegroundColor Red; return 2 }
    }

    # The old pin: a commit of this repo gives its whole tests/kit.pin; a kit
    # sha replaces sha= in the current one.
    $newBytes = [IO.File]::ReadAllBytes($pinPath)
    $newLines = @(Get-Content -LiteralPath $pinPath)
    $oldLines, $from, $shaForm = $null, $null, $false
    if ($Compare -cmatch '^-') { Write-Host "-Compare takes a commit or a sha, not '$Compare'" -ForegroundColor Red; return 2 }
    git -C $RepoRoot rev-parse --verify --quiet "$Compare^{commit}" *> $null
    if ($LASTEXITCODE -eq 0) {
        $shown = @(git -C $RepoRoot show "${Compare}:tests/kit.pin" 2>$null)
        if ($LASTEXITCODE -eq 0) { $oldLines, $from = $shown, "${Compare}:tests/kit.pin" }
    }
    if ($null -eq $oldLines) {
        if ($Compare -cnotmatch '^[0-9a-f]{40}$') {
            Write-Host "-Compare takes a commit of this repo with a tests/kit.pin (HEAD, main, ...) or the old kit sha (40 hex): '$Compare' is neither" -ForegroundColor Red
            return 2
        }
        $oldLines = @("sha=$Compare") + @($newLines | Where-Object { $_ -notmatch '^\s*sha\s*=' })
        $from = "tests/kit.pin with sha=$($Compare.Substring(0, 7))"
        $shaForm = $true
    }
    $old = ConvertFrom-WowTestKitPin $oldLines
    $new = ConvertFrom-WowTestKitPin $newLines
    $describe = { param($p) "sha $(if ($p.sha) { $p.sha.Substring(0, [Math]::Min(7, $p.sha.Length)) } else { '?' }), build $($p.build), api $($p.api)" }
    Write-Host "old pin: $(& $describe $old) ($from)"
    Write-Host "new pin: $(& $describe $new) (tests/kit.pin)"
    if ($old.sha -ceq $new.sha -and $old.build -ceq $new.build -and $old.api -ceq $new.api) {
        Write-Host "The two pins are the same: nothing to compare." -ForegroundColor Red
        return 2
    }

    $pwsh = (Get-Process -Id $PID).Path
    $logDir = Join-Path ([IO.Path]::GetTempPath()) ("WowTestKit-compare-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force $logDir | Out-Null
    $savedKit = $env:WOWTESTKIT
    # One side: tests/run.ps1 as the owner runs it, then the snapshot script
    # against the same kit.
    $runSide = {
        param($name)
        Write-Host "-- $name pin: tests\run.ps1" -ForegroundColor Cyan
        $kit = Get-WowTestKit -RepoRoot $RepoRoot
        $build = (ConvertFrom-WowTestKitPin (Get-Content -LiteralPath $pinPath)).build
        if ($shaForm -and $name -eq 'old' -and -not (Test-Path -LiteralPath (Join-Path $kit "data/forever-$build"))) {
            Write-Host "   the kit at this sha has no data for build ${build}: -Compare <a commit of this repo> takes that commit's build too" -ForegroundColor Yellow
        }
        $runArgs = @('-NoProfile', '-File', $runPs1)
        if ($Lua) { $runArgs += '-Lua', $Lua }
        Push-Location $RepoRoot
        try {
            $out = @(& $pwsh @runArgs 2>&1 | ForEach-Object { "$_" -replace "\x1b\[[0-9;?]*[A-Za-z]", '' })
            $code = $LASTEXITCODE
            $snap, $snapCode = $null, $null
            if ($Snapshot) {
                $env:WOWTESTKIT = $kit
                $snap = @(& $luaExe $Snapshot 2>&1 | ForEach-Object { "$_" })
                $snapCode = $LASTEXITCODE
                $snap | Set-Content -LiteralPath (Join-Path $logDir "$name-snapshot.txt")
            }
        } finally { Pop-Location }
        $out | Set-Content -LiteralPath (Join-Path $logDir "$name-tests.txt")
        $r = Get-WowTestKitResults $out
        Write-Host "   exit $code, $($r.Files.Count) test files: $($r.Summary)"
        @{ Results = $r; Code = $code; Snapshot = $snap; SnapshotCode = $snapCode }
    }

    try {
        [IO.File]::WriteAllBytes($backup, $newBytes)
        try {
            [IO.File]::WriteAllText($pinPath, (($oldLines -join "`n") + "`n"))
            $oldSide = & $runSide "old"
        } finally {
            [IO.File]::WriteAllBytes($pinPath, $newBytes)
            $back = [IO.File]::ReadAllBytes($pinPath)
            if ([Convert]::ToBase64String($back) -ceq [Convert]::ToBase64String($newBytes)) {
                Remove-Item -LiteralPath $backup
            } else {
                Write-Host "tests\kit.pin could not be put back: $backup holds it" -ForegroundColor Red
            }
        }
        if (Test-Path -LiteralPath $backup) { return 2 }
        $newSide = & $runSide "new"
    } finally { $env:WOWTESTKIT = $savedKit }

    # The result lines that differ, in the old run's order.
    $o, $n = $oldSide.Results, $newSide.Results
    $names = @($o.Files.Keys) + @($n.Files.Keys | Where-Object { -not $o.Files.Contains($_) })
    $differ = 0
    Write-Host ""
    foreach ($f in $names) {
        $a = if ($o.Files.Contains($f)) { $o.Files[$f] } else { "(not run)" }
        $b = if ($n.Files.Contains($f)) { $n.Files[$f] } else { "(not run)" }
        if ($a -cne $b) {
            $differ++
            Write-Host $f -ForegroundColor Yellow
            Write-Host "  old: $a"
            Write-Host "  new: $b"
        }
    }
    if ($oldSide.Code -ne $newSide.Code -or $o.Summary -cne $n.Summary) {
        $differ++
        Write-Host "summary" -ForegroundColor Yellow
        Write-Host "  old: $($o.Summary) (exit $($oldSide.Code))"
        Write-Host "  new: $($n.Summary) (exit $($newSide.Code))"
    }
    $same = $names.Count - @($names | Where-Object { ($o.Files[$_]) -cne ($n.Files[$_]) }).Count
    $color = if ($differ) { "Yellow" } else { "Green" }
    Write-Host "result lines: $same of $($names.Count) test files identical" -ForegroundColor $color

    if (-not $Snapshot) {
        Write-Host "load snapshot: not compared (pass -Snapshot <script.lua>: docs/ADOPTING.md, section 1)" -ForegroundColor Yellow
    } else {
        $sa, $sb = @($oldSide.Snapshot), @($newSide.Snapshot)
        $sameSnap = $oldSide.SnapshotCode -eq $newSide.SnapshotCode -and $sa.Count -eq $sb.Count
        for ($i = 0; $sameSnap -and $i -lt $sa.Count; $i++) { if ($sa[$i] -cne $sb[$i]) { $sameSnap = $false } }
        if ($sameSnap) {
            Write-Host "load snapshot: identical ($($sa.Count) lines, exit $($newSide.SnapshotCode))" -ForegroundColor Green
        } else {
            $differ++
            Write-Host "load snapshot: DIFFERS (old exit $($oldSide.SnapshotCode), $($sa.Count) lines; new exit $($newSide.SnapshotCode), $($sb.Count) lines)" -ForegroundColor Yellow
            $d = @(Compare-Object -CaseSensitive -ReferenceObject $sa -DifferenceObject $sb)
            $d | Select-Object -First 40 | ForEach-Object {
                $mark = if ($_.SideIndicator -eq '<=') { 'old' } else { 'new' }
                Write-Host "  ${mark}: $($_.InputObject)"
            }
            if ($d.Count -gt 40) { Write-Host "  ... and $($d.Count - 40) more" }
        }
    }
    # Identical lines from a run that failed prove nothing about the bump.
    $broken = @()
    foreach ($s in @(@('old', $oldSide), @('new', $newSide))) {
        if ($s[1].Code -ne 0) { $broken += "$($s[0]) tests (exit $($s[1].Code))" }
        if ($Snapshot -and $s[1].SnapshotCode -ne 0) { $broken += "$($s[0]) snapshot (exit $($s[1].SnapshotCode))" }
    }
    if ($broken) {
        Write-Host "FAILED: $($broken -join ', '). The comparison means little until both pass: see the full outputs." -ForegroundColor Red
    }
    Write-Host "full outputs: $logDir" -ForegroundColor DarkGray
    if ($differ -or $broken) { return 1 } else { return 0 }
}

# Run directly (not dot-sourced): the comparison.
if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -eq 0) {
        Write-Host "usage: pwsh tests/kit.ps1 -Compare <commit of this repo | old kit sha> [-Snapshot <script.lua>] [-Lua <lua.exe>]"
        exit 2
    }
    try { $code = Compare-WowTestKit @args } catch { Write-Host "-Compare: $_" -ForegroundColor Red; $code = 2 }
    exit $code
}
