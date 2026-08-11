[CmdletBinding()]
param(
    [string]$GodotPath = "",
    [string]$Manifest = "tests/regression_manifest.json",
    [string]$Filter = "",
    [switch]$SkipImport,
    [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        $candidates += $env:GODOT_BIN
    }
    foreach ($commandName in @("godot", "godot4", "Godot")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $candidates += $command.Source
        }
    }
    if ($env:USERPROFILE) {
        $candidates += Join-Path $env:USERPROFILE "Desktop\Godot_v4.7.1-stable_win64.exe"
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Godot was not found. Pass -GodotPath or set GODOT_BIN."
}

function Quote-ProcessArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-GodotProcess {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds,
        [string]$TestRunId
    )

    $argumentLine = ($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
    $originalRunId = $env:RAID_TEST_RUN_ID
    try {
        # The GameState autoload maps user:// to a unique custom directory before
        # campaign/settings autoloads read any persistent state.
        $env:RAID_TEST_RUN_ID = $TestRunId
        $startArguments = @{
            FilePath = $Executable
            WorkingDirectory = $projectRoot
            ArgumentList = $argumentLine
            PassThru = $true
            RedirectStandardOutput = $StdoutPath
            RedirectStandardError = $StderrPath
        }
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $startArguments.WindowStyle = "Hidden"
        }
        $process = Start-Process @startArguments
    } finally {
        $env:RAID_TEST_RUN_ID = $originalRunId
    }

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        return @{ ExitCode = -1; TimedOut = $true }
    }

    $process.WaitForExit()
    $process.Refresh()
    $exitCode = [int]$process.ExitCode
    return @{ ExitCode = $exitCode; TimedOut = $false }
}

function Test-UnexpectedGodotError {
    param([string]$Output, [object]$Definition)

    $errorMatches = [regex]::Matches($Output, '(?m)^(?:SCRIPT ERROR|ERROR):.*$')
    if ($errorMatches.Count -eq 0) {
        return @()
    }

    $allowed = @($Definition.allow_error_patterns)
    $unexpected = @()
    foreach ($match in $errorMatches) {
        $line = $match.Value
        $isAllowed = $false
        foreach ($pattern in $allowed) {
            if ($line -match [string]$pattern) {
                $isAllowed = $true
                break
            }
        }
        if (-not $isAllowed) {
            $unexpected += $line
        }
    }
    return $unexpected
}

$godot = Resolve-GodotExecutable $GodotPath
$manifestPath = if ([IO.Path]::IsPathRooted($Manifest)) { $Manifest } else { Join-Path $projectRoot $Manifest }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Regression manifest was not found: $manifestPath"
}

$manifestData = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([int]$manifestData.schema_version -ne 1) {
    throw "Unsupported regression manifest schema: $($manifestData.schema_version)"
}

$tests = @($manifestData.tests)
if (-not [string]::IsNullOrWhiteSpace($Filter)) {
    $tests = @($tests | Where-Object { $_.id -like "*$Filter*" -or $_.target -like "*$Filter*" })
}
if ($tests.Count -eq 0) {
    throw "The regression filter selected no tests."
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "raid-leader-regressions"
$runId = [Guid]::NewGuid().ToString("N")
$runRoot = Join-Path $testRoot $runId
$logsRoot = Join-Path $runRoot "logs"
$userDataRoot = Join-Path $runRoot "user-data"
New-Item -ItemType Directory -Path $logsRoot, $userDataRoot -Force | Out-Null

$failures = @()
try {
    if (-not $SkipImport) {
        $importOut = Join-Path $logsRoot "import.out.log"
        $importErr = Join-Path $logsRoot "import.err.log"
        $importResult = Invoke-GodotProcess $godot @(
            "--headless", "--path", ".", "--import", "--", "--raid-test"
        ) $importOut $importErr 120 "${runId}_import"
        $importOutput = (Get-Content -LiteralPath $importOut -Raw -ErrorAction SilentlyContinue) + "`n" +
            (Get-Content -LiteralPath $importErr -Raw -ErrorAction SilentlyContinue)
        if ($importResult.TimedOut -or $importResult.ExitCode -ne 0) {
            throw "Headless import failed (exit $($importResult.ExitCode)). Logs: $logsRoot"
        }
        $importErrors = Test-UnexpectedGodotError $importOutput ([pscustomobject]@{ allow_error_patterns = @() })
        if ($importErrors.Count -gt 0) {
            throw "Headless import emitted an unexpected error: $($importErrors[0])"
        }
    }

    foreach ($test in $tests) {
        $id = [string]$test.id
        $kind = [string]$test.kind
        $target = [string]$test.target
        $timeoutSeconds = if ($test.timeout_seconds) { [int]$test.timeout_seconds } else { 60 }
        $stdoutPath = Join-Path $logsRoot "$id.out.log"
        $stderrPath = Join-Path $logsRoot "$id.err.log"
        $isolatedUserData = Join-Path $userDataRoot $id
        New-Item -ItemType Directory -Path $isolatedUserData -Force | Out-Null

        $arguments = @("--headless", "--path", ".")
        if ($kind -eq "scene") {
            $arguments += $target
        } elseif ($kind -eq "script") {
            $arguments += @("--script", $target)
        } else {
            $failures += "${id}: unsupported manifest kind '$kind'"
            continue
        }
        $arguments += @("--", "--raid-test")

        Write-Host "[RUN ] $id"
        $result = Invoke-GodotProcess $godot $arguments $stdoutPath $stderrPath $timeoutSeconds "${runId}_${id}"
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        $combined = [string]$stdout + "`n" + [string]$stderr
        $passMarker = "RAID_TEST_PASS:$id"
        $failMarker = "RAID_TEST_FAIL:$id"
        $unexpectedErrors = Test-UnexpectedGodotError $combined $test
        $reasons = @()

        if ($result.TimedOut) { $reasons += "timed out after ${timeoutSeconds}s" }
        if ($result.ExitCode -ne 0) { $reasons += "process exit $($result.ExitCode)" }
        if ($combined -notmatch [regex]::Escape($passMarker)) { $reasons += "missing pass marker" }
        if ($combined -match [regex]::Escape($failMarker)) { $reasons += "reported failure marker" }
        if ($unexpectedErrors.Count -gt 0) { $reasons += "unexpected Godot error: $($unexpectedErrors[0])" }

        if ($reasons.Count -gt 0) {
            $failures += "${id}: $($reasons -join '; ')"
            Write-Host "[FAIL] $id" -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr.TrimEnd() }
        } else {
            Write-Host "[PASS] $id" -ForegroundColor Green
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "`nRegression failures ($($failures.Count))" -ForegroundColor Red
        $failures | ForEach-Object { Write-Host " - $_" }
        Write-Host "Artifacts: $logsRoot"
        exit 1
    }

    Write-Host "`nRAID_TEST_SUITE_PASS: $($tests.Count) test(s) passed."
    exit 0
} finally {
    if (-not $KeepArtifacts -and $failures.Count -eq 0) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
        if ($resolvedRunRoot.StartsWith($resolvedTestRoot + [IO.Path]::DirectorySeparatorChar)) {
            Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
