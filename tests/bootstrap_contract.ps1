# Exercise both consumer bootstraps (kit.ps1, fetch_kit.sh) against an isolated cache.
# -Bash: the bash that runs fetch_kit.sh (on Windows, Git Bash, not WSL).
param([string]$Bash = "bash")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../bootstrap/kit.ps1")
$tempRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName.TrimEnd('\', '/')
$repo = Join-Path $tempRoot ("wowtestkit-cache-" + [guid]::NewGuid())
$tests = New-Item -ItemType Directory -Path (Join-Path $repo "tests")
$pin = Join-Path $tests.FullName "kit.pin"
$oldLocal = $env:LOCALAPPDATA
$oldKit = $env:WOWTESTKIT
$oldProtocol = $env:GIT_ALLOW_PROTOCOL
$fetchKit = (Join-Path $PSScriptRoot "../bootstrap/fetch_kit.sh").Replace('\', '/')
$fetches = 0
# fetch_kit.sh on the current tests/kit.pin, into a fresh destination. The
# fetch itself is refused offline (GIT_ALLOW_PROTOCOL), after the pin is read.
function Invoke-FetchKit {
    $script:fetches++
    $dest = (Join-Path $repo "fetch-$script:fetches").Replace('\', '/')
    Push-Location $repo
    try { $out = & $Bash $fetchKit $dest 2>&1; $code = $LASTEXITCODE } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Output = ($out -join "`n") }
}
try {
    $env:LOCALAPPDATA = $repo
    $env:GIT_ALLOW_PROTOCOL = 'file'
    $cache = New-Item -ItemType Directory -Path (Join-Path $repo "WowTestKit/bad-pin")
    $sentinel = Join-Path $cache.FullName "keep.txt"
    Set-Content -LiteralPath $sentinel -Value 'keep'
    # Each case is the pin's sha= line(s). The last one counts, in both
    # bootstraps: a valid sha= followed by a malformed one is refused.
    $valid = 'a' * 40
    $cases = 'sha=bad-pin', "sha=$('g' * 40)", "sha=$('a' * 41)", "sha=$('A' * 40)",
        "sha=$valid extra", "sha=$valid`nsha=$valid extra"
    foreach ($case in $cases) {
        $sha = $case
        Set-Content -LiteralPath $pin -Value (@($case -split "`n") + 'build=70532')
        try {
            Get-WowTestKit -RepoRoot $repo
            throw "Bootstrap accepted an invalid pin"
        } catch {
            if (!$_.Exception.Message.Contains('40-hex sha')) { throw }
        }
        if ((Get-Content -LiteralPath $sentinel) -ne 'keep') { throw "Cache sentinel changed" }
        $r = Invoke-FetchKit
        if ($r.Code -ne 1 -or !$r.Output.Contains('no 40-hex sha=')) {
            throw "fetch_kit.sh accepted the pin sha=$sha (exit $($r.Code)): $($r.Output)"
        }
    }
    $checkout = Join-Path $repo 'checkout'
    git init --quiet $checkout
    if ($LASTEXITCODE) { throw "Cannot initialize fixture" }
    git -C $checkout -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet --allow-empty -m fixture
    if ($LASTEXITCODE) { throw "Cannot commit fixture" }
    $sha = git -C $checkout rev-parse HEAD
    $expected = Join-Path $cache.Parent.FullName $sha
    if ((Resolve-Path -LiteralPath $checkout).Path -ne $checkout -or
        [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($expected)) -ne $cache.Parent.FullName) {
        throw "Invalid fixture path"
    }
    Move-Item -LiteralPath $checkout -Destination $expected
    Set-Content -LiteralPath $pin -Value "sha=$sha # pinned kit", 'build=70532'
    if ((Get-WowTestKit -RepoRoot $repo) -ne $expected) { throw "Valid cached checkout was not reused" }
    # fetch_kit.sh takes the same pin (the comment dropped) and goes on to fetch it.
    $r = Invoke-FetchKit
    if ($r.Code -eq 0 -or $r.Output.Contains('no 40-hex sha=')) {
        throw "fetch_kit.sh did not take the valid pin with a comment (exit $($r.Code)): $($r.Output)"
    }
    Write-Host "Both bootstraps refused the malformed pins and took the valid one; the cache was preserved."
} finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:WOWTESTKIT = $oldKit
    $env:GIT_ALLOW_PROTOCOL = $oldProtocol
    $resolved = (Resolve-Path -LiteralPath $repo).Path
    if ($resolved -eq $repo -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
exit 0
