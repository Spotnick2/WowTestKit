# Run the same disposable consumer through both runners.
param(
    [string]$Lua = "lua5.1",
    [string]$Bash = "bash"
)
$ErrorActionPreference = "Stop"
$Lua = (Get-Command $Lua -CommandType Application | Select-Object -First 1).Source
$kit = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')
$tempRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName.TrimEnd('\', '/')
$repo = Join-Path $tempRoot ("wowtestkit-runner-" + [guid]::NewGuid())
$testDir = New-Item -ItemType Directory -Path (Join-Path $repo "tests")
$test = Join-Path $testDir.FullName "test_example.lua"
$oldLua = $env:LUA
$env:LUA = $Lua.Replace('\', '/')
Push-Location $repo
try {
    # Lua body, expected exit code, expected output. A null body means empty discovery.
    $cases = @(
        @('done("suite")', 0, 'All 1 test files passed'),
        @('check(false, "bad") done("suite")', 1, '1 of 1 test file(s) FAILED'),
        @('Kit.skip("suite", "optional")', 0, '1 skipped'),
        @('io.write("SKIPPED: optional\n")', 0, '1 skipped'),
        @('check(false, "bad") Kit.skip("suite", "optional")', 1, '1 failed'),
        @('io.write("suite: 0 passed, 1 failed\n")', 1, '1 of 1 test file(s) FAILED'),
        # Blank lines after the result don't count, in either runner.
        @('io.write("suite: 1 passed, 0 failed\n\n \n")', 0, 'All 1 test files passed'),
        @('io.write("suite: 0 passed, 1 failed\n\n")', 1, 'missing successful final test result'),
        @('check(false, "bad")', 1, 'missing successful final test result'),
        @('', 1, 'missing successful final test result'),
        @($null, 1, 'No tests/test_*.lua'),
        @('done("suite")', 1, 'absent.toc', 'absent.toc')
    )
    foreach ($case in $cases) {
        $body, $code, $message, $toc = $case
        if ($null -eq $body) {
            Remove-Item -LiteralPath $test
        } else {
            Set-Content -LiteralPath $test -Encoding utf8NoBOM -Value @(
                "dofile([[$kit/kit.lua]]) Kit.load({build='70532', api=Kit.API})"
                $body
            )
        }
        foreach ($shell in 'Bash', 'PowerShell') {
            if ($shell -eq 'Bash') {
                $runnerArgs = @("$kit/scripts/run.sh")
                if ($toc) { $runnerArgs += $toc }
                $output = & $Bash @runnerArgs 2>&1
            } else {
                $runnerArgs = @('-NoProfile', '-File', "$kit/scripts/run.ps1", '-RepoRoot', $repo, '-Lua', $Lua)
                if ($toc) { $runnerArgs += '-Toc', $toc }
                $output = & pwsh @runnerArgs 2>&1
            }
            if ($LASTEXITCODE -ne $code -or !($output -join "`n").Contains($message)) {
                throw "$shell expected exit $code and '$message' for '$body'. Got exit $LASTEXITCODE with $output"
            }
        }
    }
    Write-Host "Both runners passed all $($cases.Count) consumer cases."
} finally {
    Pop-Location
    $env:LUA = $oldLua
    $resolved = (Resolve-Path -LiteralPath $repo).Path
    if ($resolved -eq $repo -and [IO.Path]::GetDirectoryName($resolved) -eq $tempRoot) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
exit 0
