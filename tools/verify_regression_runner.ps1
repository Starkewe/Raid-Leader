[CmdletBinding()]
param([string]$GodotPath = "")

$runner = Join-Path $PSScriptRoot "run_regressions.ps1"
$hostExecutable = (Get-Process -Id $PID).Path
$arguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner,
    "-Manifest", "tests/fixtures/failing_manifest.json"
)
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $arguments += @("-GodotPath", $GodotPath)
}

$childOutput = @(& $hostExecutable @arguments 2>&1)
$childExitCode = $LASTEXITCODE
$childOutput | ForEach-Object { Write-Host $_ }

if ($childExitCode -eq 0) {
    throw "The deliberately failing exit-zero fixture was accepted by the regression runner."
}

$combinedOutput = $childOutput -join "`n"
if ($combinedOutput -notmatch [regex]::Escape("RAID_TEST_FAIL:false_positive_exit_zero")) {
    throw "The regression runner failed before executing the deliberate fixture."
}

Write-Host "RAID_TEST_HARNESS_PASS: exit-zero failure fixture was rejected."
exit 0
