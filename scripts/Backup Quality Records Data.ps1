param(
    [string]$Destination = '\\NW-APPSERVER\NWMS_QC',
    [string]$BackupRoot = '',
    [int]$KeepDays = 30
)

<#
================================================================================
 Backup Quality Records Data.ps1
================================================================================

 WHAT THIS DOES
 --------------
 Copies the live data\ folder from the Quality Records deployment to a
 timestamped folder under Backups\, verifies the copy by file count and total
 bytes, and prunes old backups.

 What is in data\, and why it is worth a scheduled task:
   data\plans\*.json        the quality records themselves
   data\plans\index.json    the records list
   data\attachments\*       PHOTOGRAPHIC EVIDENCE -- elcometer readings,
                            packing, labelling, defect reference shots
   data\library.json        the shared route templates and station FMEA library
   data\settings.json       the privileged-password hash

 A record can be retyped. A photograph cannot be retaken once the parts have
 shipped. That asymmetry is the whole reason this script exists.

 SAFE TO RUN WHILE THE SERVICE IS RUNNING
 ----------------------------------------
 Yes. This script only ever READS data\ and only ever WRITES inside Backups\.
 It does not need, take or check the service lock, so it will not interrupt
 anyone using the app.

 The one caveat, stated honestly: a plan being saved at the exact instant the
 copy passes over it could in principle be caught mid-write. In practice
 qc-api.ps1 writes every file through a .tmp file and then MOVES it over the
 real name, so a reader sees either the whole old file or the whole new one --
 never a half-written one. The residual risk is only that a backup may not
 include the very last few seconds of edits, which is not the same thing as a
 corrupt backup.

 WHERE TO RUN IT
 ---------------
 Anywhere with write access to the share -- your laptop, or a scheduled task.
 It does not execute anything on NW-APPSERVER; it is a file copy over UNC.

 PRUNING
 -------
 Backups older than -KeepDays are deleted, EXCEPT that the most recent 3 are
 always kept no matter how old they are. So a folder that has not been backed
 up for a year does not get emptied out by a single run.

 Only folders this script's own naming scheme created (Backups\data-<stamp>\)
 are ever considered for pruning. Anything else in Backups\ is left alone.

 SCHEDULED TASK
 --------------
 The last line of output is a single-line summary, so a scheduled task's log
 is readable at a glance. Exit code 0 = verified backup taken, 1 = it failed.

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File
     "<path>\scripts\Backup Quality Records Data.ps1"
================================================================================
#>

$ErrorActionPreference = 'Stop'

$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if (-not (Test-Path -LiteralPath $destinationPath)) {
    throw "Deployment folder is unavailable: $destinationPath"
}

$sourceData = Join-Path $destinationPath 'data'
if (-not (Test-Path -LiteralPath $sourceData -PathType Container)) {
    throw "There is no data\ folder to back up at $sourceData. Check -Destination is the right deployment folder."
}

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $BackupRoot = Join-Path $destinationPath 'Backups'
}
$backupRootPath = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')

# Refuse to write backups inside the folder being backed up: a backup nested in
# data\ would be copied into the next backup, doubling in size every run.
if ($backupRootPath -ieq $sourceData -or $backupRootPath.StartsWith($sourceData + '\', 'OrdinalIgnoreCase')) {
    throw "-BackupRoot ($backupRootPath) is inside the data folder being backed up ($sourceData). Each backup would then be copied into the next one. Pick somewhere else."
}

# The service's lock file is excluded from EVERYTHING here -- the stats and the
# copy alike. It is held open with FileShare::None for the whole life of the
# service, so any attempt to read it throws; and it is runtime state, not data
# worth keeping. Excluding it from the stats too is what keeps the count/byte
# verification honest, since the copy will not contain it either.
$script:LockFileName = 'qc-api.lock'

function Get-BackupSourceFiles {
    param([string]$Path)
    return @(
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $script:LockFileName }
    )
}

function Get-TreeStats {
    param([string]$Path)
    $files = Get-BackupSourceFiles -Path $Path
    $bytes = 0
    foreach ($file in $files) { $bytes = $bytes + $file.Length }
    return New-Object psobject -Property @{ Count = $files.Count; Bytes = $bytes }
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1048576) { return ([math]::Round($Bytes / 1048576, 1).ToString() + ' MB') }
    if ($Bytes -ge 1024) { return ([math]::Round($Bytes / 1024, 1).ToString() + ' KB') }
    return ($Bytes.ToString() + ' bytes')
}

$stamp     = [datetime]::Now.ToString('yyyyMMdd-HHmmss')
$backupDir = Join-Path $backupRootPath ('data-' + $stamp)

Write-Host ''
Write-Host '=== NWMS Quality Records - Data Backup ===' -ForegroundColor Cyan
Write-Host ("Source      : " + $sourceData)
Write-Host ("Backup to   : " + $backupDir)
Write-Host ("Keep days   : " + $KeepDays + '  (the most recent 3 are always kept)')
Write-Host 'Safe to run while the service is running -- this only reads data\.'
Write-Host ''

$sourceStats = Get-TreeStats -Path $sourceData
if ($sourceStats.Count -eq 0) {
    Write-Warning "data\ is empty ($sourceData). Backing it up anyway so the run is honest about what it found, but check this is the right -Destination."
}

$attachmentsDir = Join-Path $sourceData 'attachments'
$attachmentCount = 0
if (Test-Path -LiteralPath $attachmentsDir -PathType Container) {
    $attachmentCount = (Get-TreeStats -Path $attachmentsDir).Count
}
$plansDir = Join-Path $sourceData 'plans'
$planCount = 0
if (Test-Path -LiteralPath $plansDir -PathType Container) {
    $planCount = @(Get-ChildItem -LiteralPath $plansDir -File | Where-Object { $_.Extension -ieq '.json' -and $_.Name -ne 'index.json' }).Count
}

Write-Host ('Found ' + $sourceStats.Count + ' files, ' + (Format-Bytes $sourceStats.Bytes) + ' (' + $planCount + ' plan records, ' + $attachmentCount + ' attachment files)')

# ------------------------------------------------------------------------------
# Copy and verify
# ------------------------------------------------------------------------------
[void][IO.Directory]::CreateDirectory($backupRootPath)
if (Test-Path -LiteralPath $backupDir) {
    throw "A backup folder for this second already exists: $backupDir. Wait a second and run again."
}

# Copied file by file rather than with one Copy-Item -Recurse, and the reason
# matters: a recursive copy also tries to copy data\qc-api.lock, which the
# running service holds with FileShare::None. That throws, and with
# $ErrorActionPreference = 'Stop' it aborts the run part-way through -- so the
# nightly backup would fail EVERY night on a server where the service is always
# up, which is precisely when the backup is the only thing standing between a
# lost photograph and a retake that cannot happen.
[void][IO.Directory]::CreateDirectory($backupDir)
foreach ($file in (Get-BackupSourceFiles -Path $sourceData)) {
    $relative = $file.FullName.Substring($sourceData.Length).TrimStart('\')
    $target   = Join-Path $backupDir $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}

$backupStats = Get-TreeStats -Path $backupDir
if ($backupStats.Count -ne $sourceStats.Count -or $backupStats.Bytes -ne $sourceStats.Bytes) {
    # Renamed out of the data-<stamp> namespace before we throw. A half-copied
    # folder that still matches that pattern is indistinguishable by name from a
    # verified one: it would be offered by the rollback's backup listing, and
    # three failed nightly runs would occupy all three "most recent are always
    # kept" prune slots while genuine backups aged out behind them.
    $failedName = (Split-Path $backupDir -Leaf) + '.FAILED'
    $failedPath = Join-Path (Split-Path $backupDir -Parent) $failedName
    try {
        Rename-Item -LiteralPath $backupDir -NewName $failedName -Force
    }
    catch {
        $failedPath = $backupDir  # could not rename; name it as-is in the error
    }
    throw @"
BACKUP VERIFICATION FAILED -- this backup is NOT usable.

  source : $($sourceStats.Count) files, $($sourceStats.Bytes) bytes
  backup : $($backupStats.Count) files, $($backupStats.Bytes) bytes
  at     : $failedPath

The live data\ folder has not been altered -- this script only reads it. The
part-copied folder has been renamed with a .FAILED suffix so it can never be
mistaken for a good backup or offered by a restore; delete it once you have
looked at it.

A count/byte difference is usually free space, share permissions, or a plan
saved by the service mid-copy. Older backups have NOT been pruned, so nothing
has been lost either way.
"@
}

Write-Host ('Verified: ' + $backupStats.Count + ' files, ' + (Format-Bytes $backupStats.Bytes) + ' -- count and total bytes match.') -ForegroundColor Green

# ------------------------------------------------------------------------------
# Prune -- only after a verified backup exists, never before
# ------------------------------------------------------------------------------
$allBackups = @(
    Get-ChildItem -LiteralPath $backupRootPath -Directory |
        Where-Object { $_.Name -match '^data-\d{8}-\d{6}(-rollback)?$' } |
        Sort-Object Name -Descending
)

$prunedCount = 0
$prunedBytes = 0
$cutoff = (Get-Date).AddDays(-1 * [math]::Abs($KeepDays))

# The most recent 3 are exempt from pruning whatever their age: a folder nobody
# has backed up in a year must not end up with zero backups because of it.
for ($index = 3; $index -lt $allBackups.Count; $index++) {
    $candidate = $allBackups[$index]
    if ($candidate.FullName -ieq $backupDir) { continue }
    if ($candidate.LastWriteTime -ge $cutoff) { continue }
    $stats = Get-TreeStats -Path $candidate.FullName
    Remove-Item -LiteralPath $candidate.FullName -Recurse -Force
    $prunedCount = $prunedCount + 1
    $prunedBytes = $prunedBytes + $stats.Bytes
    Write-Host ('Pruned old backup: ' + $candidate.Name + ' (' + (Format-Bytes $stats.Bytes) + ')')
}

$remaining = @(
    Get-ChildItem -LiteralPath $backupRootPath -Directory |
        Where-Object { $_.Name -match '^data-\d{8}-\d{6}(-rollback)?$' }
).Count

Write-Host ''
Write-Host ('OK ' + $stamp + ' - backed up ' + $backupStats.Count + ' files (' + (Format-Bytes $backupStats.Bytes) + ') to ' + $backupDir + ' - verified - pruned ' + $prunedCount + ' old backup(s) (' + (Format-Bytes $prunedBytes) + ') - ' + $remaining + ' backup(s) retained') -ForegroundColor Green
exit 0
