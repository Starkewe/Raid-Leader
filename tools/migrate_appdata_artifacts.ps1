[CmdletBinding()]
param(
    [string]$RoamingRoot = "",
    [string]$ManifestPath = "",
    [switch]$Preview
)

# One-time usage from the project root:
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\migrate_appdata_artifacts.ps1
# The default destination is the current user's ApplicationData (APPDATA) root.

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$cacheRoot = Join-Path $projectRoot ".godot"
if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
    throw "Godot cache was not found: $cacheRoot"
}

if ([string]::IsNullOrWhiteSpace($RoamingRoot)) {
    $RoamingRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
}
$RoamingRoot = [IO.Path]::GetFullPath($RoamingRoot)
if (-not (Test-Path -LiteralPath $RoamingRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $RoamingRoot -Force | Out-Null
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.Path]::GetFullPath($Path)
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = (Get-FullPath $Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = (Get-FullPath $Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    $sha = $null
    try {
        # Allow hashing the live Godot log while the editor has it open.
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace "-", "").ToUpperInvariant()
    } finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-HashIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = [ordered]@{
        Hash  = $null
        Error = $null
    }
    try {
        $result.Hash = Get-Sha256 $Path
    } catch {
        $result.Error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Get-RelativePathFrom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = Get-FullPath $Path
    $fullRoot = (Get-FullPath $Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-PathWithin $fullPath $fullRoot) -or $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not a child of the expected root. Path='$fullPath' Root='$fullRoot'"
    }
    return $fullPath.Substring($fullRoot.Length + 1)
}

function Get-UtcTicks {
    param([Parameter(Mandatory = $true)][IO.FileSystemInfo]$Item)
    return [ordered]@{
        CreationTimeUtc = $Item.CreationTimeUtc.Ticks
        LastWriteTimeUtc = $Item.LastWriteTimeUtc.Ticks
        LastAccessTimeUtc = $Item.LastAccessTimeUtc.Ticks
        Attributes = [int]$Item.Attributes
    }
}

function Convert-TicksToUtc {
    param([Parameter(Mandatory = $true)][long]$Ticks)
    return [DateTime]::new($Ticks, [DateTimeKind]::Utc)
}

function Set-EntryMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Metadata
    )

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        $item.Attributes = [IO.FileAttributes]::Normal
    } else {
        # Clear read-only before setting timestamps, then restore source attributes.
        $item.Attributes = [IO.FileAttributes]::Normal
    }
    $item.CreationTimeUtc = Convert-TicksToUtc ([long]$Metadata.CreationTimeUtc)
    $item.LastWriteTimeUtc = Convert-TicksToUtc ([long]$Metadata.LastWriteTimeUtc)
    $item.LastAccessTimeUtc = Convert-TicksToUtc ([long]$Metadata.LastAccessTimeUtc)
    $item.Attributes = [IO.FileAttributes]$Metadata.Attributes
}

function Assert-NoReparsePoints {
    param([Parameter(Mandatory = $true)][string]$Root)

    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to migrate a reparse point inside '$Root': $($item.FullName)"
        }
    }
}

function Get-DestinationPath {
    param(
        [Parameter(Mandatory = $true)][IO.DirectoryInfo]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $relative = Get-RelativePathFrom $SourcePath $SourceRoot.FullName
    $topLevel = ($relative -split "[\\/]")[0]
    if ($topLevel -eq "Godot" -or $topLevel.StartsWith("raid_leader_tests_", [StringComparison]::Ordinal)) {
        $destinationRelative = $relative
        $logPrefix = "Godot\app_userdata\Raid Leader\logs\"
        if ($relative.StartsWith($logPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            # Keep imported logs below the live log directory but outside its
            # rotation set. Godot may delete old files from the live directory
            # when another editor or headless test starts.
            $logName = $relative.Substring($logPrefix.Length)
            $destinationRelative = $logPrefix + "migration-archive\" + $runId + "\" + $SourceRoot.Name + "\" + $logName
        }
        $destination = Join-Path $RoamingRoot $destinationRelative
        if (-not (Test-PathWithin $destination $RoamingRoot)) {
            throw "Calculated destination escaped the C: AppData root: $destination"
        }
        return $destination
    }
    throw "Unsupported generated AppData payload '$topLevel' under '$($SourceRoot.FullName)'."
}

function Get-AvailableConflictPath {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRootName,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $destinationRelative = Get-RelativePathFrom $DestinationPath $RoamingRoot
    $base = Join-Path (Join-Path (Join-Path $RoamingRoot "migration-conflicts") $runId) $SourceRootName
    $candidate = Join-Path $base $destinationRelative
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $directory = Split-Path -Parent $candidate
    $name = Split-Path -Leaf $candidate
    $extension = [IO.Path]::GetExtension($name)
    $stem = if ([string]::IsNullOrEmpty($extension)) { $name } else { $name.Substring(0, $name.Length - $extension.Length) }
    $index = 2
    do {
        $suffixName = if ([string]::IsNullOrEmpty($extension)) { "$stem.$index" } else { "$stem.$index$extension" }
        $candidate = Join-Path $directory $suffixName
        $index++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Copy-And-VerifyFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][object]$Metadata
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        throw "Refusing to overwrite an existing path: $DestinationPath"
    }
    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [IO.File]::Copy($SourcePath, $DestinationPath, $false)
    $destinationHash = Get-Sha256 $DestinationPath
    if ($destinationHash -ne $ExpectedHash) {
        throw "Hash verification failed after copying '$SourcePath' to '$DestinationPath'. Expected $ExpectedHash, got $destinationHash."
    }
    $sourceAfterCopyHash = Get-Sha256 $SourcePath
    if ($sourceAfterCopyHash -ne $ExpectedHash) {
        throw "Source changed while copying '$SourcePath'; it was retained for safety."
    }
    # Hashing updates Windows last-access time. Restore all source metadata only
    # after the final hash reads, so the verified destination keeps the source
    # timestamps when it is handed off.
    Set-EntryMetadata $DestinationPath $Metadata
    $destinationItem = Get-Item -LiteralPath $DestinationPath -Force
    if ($destinationItem.CreationTimeUtc.Ticks -ne [long]$Metadata.CreationTimeUtc -or
        $destinationItem.LastWriteTimeUtc.Ticks -ne [long]$Metadata.LastWriteTimeUtc -or
        $destinationItem.LastAccessTimeUtc.Ticks -ne [long]$Metadata.LastAccessTimeUtc) {
        throw "Timestamp verification failed after copying '$SourcePath' to '$DestinationPath'."
    }
    Remove-Item -LiteralPath $SourcePath -Force
    if (Test-Path -LiteralPath $SourcePath) {
        throw "Source was not removed after verified copy: $SourcePath"
    }
}

function Remove-EmptyDirectories {
    param([Parameter(Mandatory = $true)][IO.DirectoryInfo]$Root)

    $removed = @()
    $deferred = @()
    $directories = @(Get-ChildItem -LiteralPath $Root.FullName -Recurse -Directory -Force |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($directory in $directories) {
        if (@(Get-ChildItem -LiteralPath $directory.FullName -Force).Count -eq 0) {
            try {
                Remove-Item -LiteralPath $directory.FullName -Force
                $removed += $directory.FullName
            } catch {
                # A running Godot process can hold an otherwise-empty cache
                # directory open. Leave it in place and retry on the next run.
                $deferred += $directory.FullName
            }
        }
    }
    return [pscustomobject]@{
        Removed = $removed
        Deferred = $deferred
    }
}

$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$sourceRoots = @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force |
    Where-Object {
        $_.Name -like "manual-appdata*" -or
        $_.Name -like "manual-full-appdata*" -or
        $_.Name -like "regression-appdata*" -or
        $_.Name -eq "sandbox_appdata"
    } | Sort-Object Name)

foreach ($sourceRoot in $sourceRoots) {
    if (-not (Test-PathWithin $sourceRoot.FullName $cacheRoot)) {
        throw "Source root escaped the E: Godot cache: $($sourceRoot.FullName)"
    }
    Assert-NoReparsePoints $sourceRoot.FullName
    foreach ($topLevel in @(Get-ChildItem -LiteralPath $sourceRoot.FullName -Force)) {
        if (-not $topLevel.PSIsContainer) {
            throw "Unexpected file directly under AppData payload root: $($topLevel.FullName)"
        }
        if ($topLevel.Name -ne "Godot" -and -not $topLevel.Name.StartsWith("raid_leader_tests_", [StringComparison]::Ordinal)) {
            throw "Unsupported top-level generated AppData directory: $($topLevel.FullName)"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $cacheRoot "appdata-migration-$runId-manifest.json"
} elseif (-not [IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath = Join-Path $projectRoot $ManifestPath
}
$ManifestPath = Get-FullPath $ManifestPath
if (-not (Test-PathWithin $ManifestPath $projectRoot)) {
    throw "The manifest must be kept inside the project workspace: $ManifestPath"
}
$resultManifestPath = [IO.Path]::Combine(
    [IO.Path]::GetDirectoryName($ManifestPath),
    ([IO.Path]::GetFileNameWithoutExtension($ManifestPath) + "-result.json")
)

$directoryEntries = @()
$fileEntries = @()
foreach ($sourceRoot in $sourceRoots) {
    foreach ($directory in @(Get-ChildItem -LiteralPath $sourceRoot.FullName -Recurse -Directory -Force |
            Sort-Object { $_.FullName.Length })) {
        $destination = Get-DestinationPath $sourceRoot $directory.FullName
        $destinationExists = Test-Path -LiteralPath $destination -PathType Container
        if ((Test-Path -LiteralPath $destination) -and -not $destinationExists) {
            throw "A destination file blocks the generated AppData directory: $destination"
        }
        $metadata = Get-UtcTicks $directory
        $directoryEntries += [pscustomobject][ordered]@{
            SourceRoot = $sourceRoot.Name
            SourcePath = $directory.FullName
            SourceRelativePath = Get-RelativePathFrom $directory.FullName $sourceRoot.FullName
            DestinationPath = $destination
            DestinationExistsAtManifest = $destinationExists
            SourceCreationTimeUtcTicks = $metadata.CreationTimeUtc
            SourceLastWriteTimeUtcTicks = $metadata.LastWriteTimeUtc
            SourceLastAccessTimeUtcTicks = $metadata.LastAccessTimeUtc
            SourceAttributes = $metadata.Attributes
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot.FullName -Recurse -File -Force |
            Sort-Object FullName)) {
        $destination = Get-DestinationPath $sourceRoot $file.FullName
        $metadata = Get-UtcTicks $file
        $sourceHash = Get-Sha256 $file.FullName
        $destinationExists = Test-Path -LiteralPath $destination -PathType Leaf
        $destinationHash = $null
        $destinationHashError = $null
        if ((Test-Path -LiteralPath $destination) -and -not $destinationExists) {
            throw "A destination directory blocks the generated AppData file: $destination"
        }
        if ($destinationExists) {
            $destinationState = Get-HashIfPresent $destination
            $destinationHash = $destinationState.Hash
            $destinationHashError = $destinationState.Error
        }
        $plannedAction = if (-not $destinationExists) {
            "move"
        } elseif ($destinationHash -eq $sourceHash) {
            "remove-duplicate"
        } else {
            "preserve-conflict"
        }
        $plannedConflictPath = $null
        if ($plannedAction -eq "preserve-conflict") {
            $plannedConflictPath = Get-AvailableConflictPath $sourceRoot.Name $destination
        }
        $fileEntries += [pscustomobject][ordered]@{
            SourceRoot = $sourceRoot.Name
            SourcePath = $file.FullName
            SourceRelativePath = Get-RelativePathFrom $file.FullName $sourceRoot.FullName
            DestinationPath = $destination
            SourceBytes = $file.Length
            SourceSha256 = $sourceHash
            SourceCreationTimeUtcTicks = $metadata.CreationTimeUtc
            SourceLastWriteTimeUtcTicks = $metadata.LastWriteTimeUtc
            SourceLastAccessTimeUtcTicks = $metadata.LastAccessTimeUtc
            SourceAttributes = $metadata.Attributes
            DestinationExistsAtManifest = $destinationExists
            DestinationBytesAtManifest = if ($destinationExists) { (Get-Item -LiteralPath $destination -Force).Length } else { $null }
            DestinationSha256AtManifest = $destinationHash
            DestinationHashErrorAtManifest = $destinationHashError
            PlannedAction = $plannedAction
            PlannedConflictPath = $plannedConflictPath
        }
    }
}

$manifest = [ordered]@{
    SchemaVersion = 1
    Purpose = "Relocate generated Raid Leader Godot AppData payloads from the E: .godot cache to C: AppData."
    RunId = $runId
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    ProjectRoot = $projectRoot
    SourceCacheRoot = $cacheRoot
    DestinationRoamingRoot = $RoamingRoot
    SourceRoots = @($sourceRoots | ForEach-Object { $_.FullName })
    Directories = $directoryEntries
    Files = $fileEntries
}
$manifestDirectory = Split-Path -Parent $ManifestPath
if (-not (Test-Path -LiteralPath $manifestDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

$results = @()
$removedDirectories = @()
$deferredDirectories = @()
$errorRecord = $null
try {
    if ($Preview) {
        Write-Host "Preview only; no payloads will be changed."
    } else {
        # Create destination directories first, including empty raid-test directories.
        foreach ($entry in $directoryEntries) {
            if (-not (Test-Path -LiteralPath $entry.DestinationPath -PathType Container)) {
                New-Item -ItemType Directory -Path $entry.DestinationPath -Force | Out-Null
                $entry | Add-Member -NotePropertyName CreatedDestination -NotePropertyValue $true
            } else {
                $entry | Add-Member -NotePropertyName CreatedDestination -NotePropertyValue $false
            }
        }

        foreach ($entry in $fileEntries) {
            if (-not (Test-Path -LiteralPath $entry.SourcePath -PathType Leaf)) {
                throw "Manifest source file disappeared before migration: $($entry.SourcePath)"
            }
            $currentSourceHash = Get-Sha256 $entry.SourcePath
            if ($currentSourceHash -ne $entry.SourceSha256) {
                throw "Source changed after manifest creation: $($entry.SourcePath)"
            }

            $destinationExists = Test-Path -LiteralPath $entry.DestinationPath -PathType Leaf
            if ((Test-Path -LiteralPath $entry.DestinationPath) -and -not $destinationExists) {
                throw "A destination directory appeared where a file is required: $($entry.DestinationPath)"
            }
            $metadata = [pscustomobject]@{
                CreationTimeUtc = $entry.SourceCreationTimeUtcTicks
                LastWriteTimeUtc = $entry.SourceLastWriteTimeUtcTicks
                LastAccessTimeUtc = $entry.SourceLastAccessTimeUtcTicks
                Attributes = $entry.SourceAttributes
            }

            if (-not $destinationExists) {
                Copy-And-VerifyFile $entry.SourcePath $entry.DestinationPath $entry.SourceSha256 $metadata
                $results += [pscustomobject]@{
                    SourcePath = $entry.SourcePath
                    DestinationPath = $entry.DestinationPath
                    Action = "moved"
                    VerifiedSha256 = $entry.SourceSha256
                    ConflictPath = $null
                }
                continue
            }

            $destinationState = Get-HashIfPresent $entry.DestinationPath
            if ($destinationState.Hash -eq $entry.SourceSha256) {
                Remove-Item -LiteralPath $entry.SourcePath -Force
                if (Test-Path -LiteralPath $entry.SourcePath) {
                    throw "Duplicate source was not removed: $($entry.SourcePath)"
                }
                $results += [pscustomobject]@{
                    SourcePath = $entry.SourcePath
                    DestinationPath = $entry.DestinationPath
                    Action = "duplicate-removed"
                    VerifiedSha256 = $destinationState.Hash
                    ConflictPath = $null
                }
                continue
            }

            $conflictPath = Get-AvailableConflictPath $entry.SourceRoot $entry.DestinationPath
            Copy-And-VerifyFile $entry.SourcePath $conflictPath $entry.SourceSha256 $metadata
            $results += [pscustomobject]@{
                SourcePath = $entry.SourcePath
                DestinationPath = $entry.DestinationPath
                Action = "conflict-preserved"
                VerifiedSha256 = $entry.SourceSha256
                ConflictPath = $conflictPath
            }
        }

        # Set timestamps only on newly-created destination directories. Existing C:
        # directories are authoritative and keep their own metadata.
        foreach ($entry in @($directoryEntries | Sort-Object { $_.DestinationPath.Length } -Descending)) {
            if ([bool]$entry.CreatedDestination -and (Test-Path -LiteralPath $entry.DestinationPath -PathType Container)) {
                $directoryMetadata = [pscustomobject]@{
                    CreationTimeUtc = $entry.SourceCreationTimeUtcTicks
                    LastWriteTimeUtc = $entry.SourceLastWriteTimeUtcTicks
                    LastAccessTimeUtc = $entry.SourceLastAccessTimeUtcTicks
                    Attributes = $entry.SourceAttributes
                }
                Set-EntryMetadata $entry.DestinationPath $directoryMetadata
            }
        }

        foreach ($sourceRoot in $sourceRoots) {
            $cleanup = Remove-EmptyDirectories $sourceRoot
            $removedDirectories += @($cleanup.Removed)
            $deferredDirectories += @($cleanup.Deferred)
            if (Test-Path -LiteralPath $sourceRoot.FullName) {
                $remaining = @(Get-ChildItem -LiteralPath $sourceRoot.FullName -Recurse -Force)
                $remainingFiles = @($remaining | Where-Object { -not $_.PSIsContainer })
                if ($remainingFiles.Count -gt 0) {
                    throw "Source AppData root still contains files after migration: $($sourceRoot.FullName)"
                }
                if ($remaining.Count -eq 0) {
                    try {
                        Remove-Item -LiteralPath $sourceRoot.FullName -Force
                        $removedDirectories += $sourceRoot.FullName
                    } catch {
                        $deferredDirectories += $sourceRoot.FullName
                    }
                } else {
                    $deferredDirectories += @($remaining | Where-Object PSIsContainer | ForEach-Object FullName)
                }
            }
        }
    }
} catch {
    $errorRecord = $_.Exception.ToString()
    throw
} finally {
    $result = [ordered]@{
        SchemaVersion = 1
        RunId = $runId
        ManifestPath = $ManifestPath
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        Preview = [bool]$Preview
        Error = $errorRecord
        Results = $results
        RemovedDirectories = $removedDirectories
        DeferredDirectories = $deferredDirectories
        Summary = [ordered]@{
            FilesInManifest = $fileEntries.Count
            FilesCompleted = $results.Count
            Moved = @($results | Where-Object Action -eq "moved").Count
            DuplicateRemoved = @($results | Where-Object Action -eq "duplicate-removed").Count
            ConflictsPreserved = @($results | Where-Object Action -eq "conflict-preserved").Count
            DirectoriesRemoved = $removedDirectories.Count
            DirectoriesDeferred = $deferredDirectories.Count
        }
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultManifestPath -Encoding UTF8
}

Write-Host "AppData migration complete."
Write-Host ("  Manifest: " + $ManifestPath)
Write-Host ("  Result:   " + $resultManifestPath)
Write-Host ("  Files:    " + $results.Count + "/" + $fileEntries.Count + " completed")
Write-Host ("  Moved:    " + @($results | Where-Object Action -eq "moved").Count)
Write-Host ("  Duplicates removed: " + @($results | Where-Object Action -eq "duplicate-removed").Count)
Write-Host ("  Conflicts preserved: " + @($results | Where-Object Action -eq "conflict-preserved").Count)
if ($deferredDirectories.Count -gt 0) {
    Write-Warning ("  Empty source directories deferred because they are in use: " + ($deferredDirectories -join ", "))
}
