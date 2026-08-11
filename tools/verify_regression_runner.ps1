[CmdletBinding()]
param([string]$GodotPath = "")

$runner = Join-Path $PSScriptRoot "run_regressions.ps1"
$hostExecutable = (Get-Process -Id $PID).Path
$arguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner,
    "-Manifest", "tests/fixtures/failing_manifest.json", "-SkipImport"
)
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $arguments += @("-GodotPath", $GodotPath)
}

& $hostExecutable @arguments
if ($LASTEXITCODE -eq 0) {
    throw "The deliberately failing exit-zero fixture was accepted by the regression runner."
}

Write-Host "RAID_TEST_HARNESS_PASS: exit-zero failure fixture was rejected."
