# Exercise the consumer bootstrap against an isolated cache.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../bootstrap/kit.ps1")
$tempRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName.TrimEnd('\', '/')
$repo = Join-Path $tempRoot ("wowtestkit-cache-" + [guid]::NewGuid())
$tests = New-Item -ItemType Directory -Path (Join-Path $repo "tests")
$pin = Join-Path $tests.FullName "kit.pin"
$oldLocal = $env:LOCALAPPDATA
$oldKit = $env:WOWTESTKIT
$oldProtocol = $env:GIT_ALLOW_PROTOCOL
try {
    $env:LOCALAPPDATA = $repo
    $env:GIT_ALLOW_PROTOCOL = 'file'
    $cache = New-Item -ItemType Directory -Path (Join-Path $repo "WowTestKit/bad-pin")
    $sentinel = Join-Path $cache.FullName "keep.txt"
    Set-Content -LiteralPath $sentinel -Value 'keep'
    foreach ($sha in 'bad-pin', ('g' * 40), ('a' * 41), ('A' * 40), (('a' * 40) + ' extra')) {
        Set-Content -LiteralPath $pin -Value "sha=$sha", 'build=70532'
        try {
            Get-WowTestKit -RepoRoot $repo
            throw "Bootstrap accepted an invalid pin"
        } catch {
            if (!$_.Exception.Message.Contains('40-hex sha')) { throw }
        }
        if ((Get-Content -LiteralPath $sentinel) -ne 'keep') { throw "Cache sentinel changed" }
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
    Write-Host "Malformed pins preserved the cache and a valid pin worked offline."
} finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:WOWTESTKIT = $oldKit
    $env:GIT_ALLOW_PROTOCOL = $oldProtocol
    $resolved = (Resolve-Path -LiteralPath $repo).Path
    if ($resolved -eq $repo -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
