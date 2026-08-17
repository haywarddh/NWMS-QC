param(
    [string]$Destination = '\\NW-APPSERVER\NWMS_QC',
    [string]$NetworkUrl = 'http://nw-appserver:8791',
    [string]$Release = '',
    [switch]$RestoreData,
    [switch]$List,
    [switch]$WhatIf
)

<#
================================================================================
 Rollback Quality Records.ps1
================================================================================

 WHAT THIS DOES
 --------------
 Puts back a previous release of the NWMS Quality Records app from the
 snapshots that "Publish Quality Records.ps1" already takes.

 THE MENTAL MODEL, and it matters:
   Releases\<stamp>\   is the CODE that was live immediately BEFORE the
                       operation at that timestamp.
   Backups\data-<stamp>\ is the DATA as it was at that same moment.

 So "roll back to <stamp>" means "put back the code that was running just
 before that publish".

 CODE AND DATA ARE NOT THE SAME DECISION
 ---------------------------------------
 Restoring old CODE against current data is usually right -- that is what a
 bad release needs.

 Restoring old DATA is almost never right, and is off by default. It requires
 -RestoreData and a typed confirmation, because it DESTROYS every quality
 record, every sign-off and every photograph created since that backup was
 taken. A photograph cannot be retaken after the parts have shipped. Only use
 it when the DATA itself is the problem (a corrupt index.json, a mass
 deletion), never merely because the code was wrong.

 WHERE TO RUN IT
 ---------------
 On YOUR LAPTOP. Like the publisher, it only ever writes to the network share.
 NOTHING is executed on NW-APPSERVER -- you stop and start the service there
 by hand.

 WHAT IT REFUSES TO DO
 ---------------------
  1. Run while the service is running (data\qc-api.lock is held).
  2. Restore a release whose snapshot folder is missing or incomplete.
  3. Restore data without -RestoreData AND a typed confirmation.
  4. Restore data without first taking a VERIFIED backup of the data it is
     about to overwrite.

 USAGE
 -----
   Rollback Quality Records.ps1 -List
   Rollback Quality Records.ps1 -WhatIf
   Rollback Quality Records.ps1
   Rollback Quality Records.ps1 -Release 20260817-142530
   Rollback Quality Records.ps1 -Release 20260817-142530 -RestoreData
================================================================================
#>

$ErrorActionPreference = 'Stop'

$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if (-not (Test-Path -LiteralPath $destinationPath)) {
    throw "Network deployment folder is unavailable: $destinationPath"
}

$releasesRoot       = Join-Path $destinationPath 'Releases'
$backupsRoot        = Join-Path $destinationPath 'Backups'
$destinationData    = Join-Path $destinationPath 'data'
$destinationLock    = Join-Path $destinationData 'qc-api.lock'
$destinationWeb     = Join-Path $destinationPath 'web'
$destinationScripts = Join-Path $destinationPath 'scripts'
$rollbackLockPath   = Join-Path $destinationPath '.publish.lock'

$apiFiles = @('qc-api.ps1', 'README.md', 'CHANGELOG.md')
$protectedFolders = @('data', 'Backups', 'Releases')

# ------------------------------------------------------------------------------
# Helpers (kept deliberately identical in wording to the publisher's, so a
# diff between the two scripts shows real differences only)
# ------------------------------------------------------------------------------
function Get-TreeStats {
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
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

function Assert-SafeWriteTarget {
    param(
        [string]$Path,
        [string]$Allow = ''
    )
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($Allow) {
        $allowFull = [IO.Path]::GetFullPath($Allow).TrimEnd('\')
        if ($full -ieq $allowFull -or $full.StartsWith($allowFull + '\', 'OrdinalIgnoreCase')) { return }
    }
    foreach ($folder in $protectedFolders) {
        $guarded = (Join-Path $destinationPath $folder).TrimEnd('\')
        if ($full -ieq $guarded -or $full.StartsWith($guarded + '\', 'OrdinalIgnoreCase')) {
            throw "INTERNAL SAFETY STOP: refused to write inside the protected folder '$folder': $full"
        }
    }
}

function Test-ServiceLockHeld {
    param([string]$LockFile)
    if (-not (Test-Path -LiteralPath $LockFile)) { return $false }
    try {
        $openArgs = @(
            $LockFile,
            [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        $stream = New-Object System.IO.FileStream -ArgumentList $openArgs
        $stream.Dispose()
        return $false
    }
    catch {
        return $true
    }
}

function Get-ServiceVersion {
    param([string]$ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) { return '(none)' }
    $text = Get-Content -LiteralPath $ScriptPath -Raw
    $match = [regex]::Match($text, "\`$ServiceVersion\s*=\s*'([^']+)'")
    if ($match.Success) { return $match.Groups[1].Value }
    return '(not found)'
}

# Every folder in Releases\ whose name is a timestamp, newest first.
#
# Note what this deliberately does NOT do: it does not trust a manifest to tell
# it what to restore. It reads the snapshot FOLDER and restores what is actually
# in it. Manifests are only read for the human-readable version numbers below --
# so a missing or unreadable manifest degrades the listing, never the restore.
# (ConvertTo-Json in PowerShell 5.1 also collapses a one-element array to a bare
# scalar on the way out, which is one more reason not to drive a restore from it.)
function Get-AvailableReleases {
    if (-not (Test-Path -LiteralPath $releasesRoot -PathType Container)) { return @() }
    $found = New-Object System.Collections.ArrayList
    $candidates = @(Get-ChildItem -LiteralPath $releasesRoot -Directory | Sort-Object Name -Descending)
    foreach ($candidate in $candidates) {
        # Publish stamps are yyyyMMdd-HHmmss; a rollback's own undo snapshot adds
        # "-rollback". Both are listable and restorable -- you may well want to
        # undo a rollback -- so the pattern accepts the optional suffix.
        if ($candidate.Name -notmatch '^\d{8}-\d{6}(-rollback)?$') { continue }
        $kind = '(no manifest)'
        $replaced = '?'
        $published = '?'
        $by = ''
        $manifestPath = Join-Path $candidate.FullName 'manifest.json'
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $kind = [string]$manifest.kind
                $replaced = [string]$manifest.replacedVersion
                $published = [string]$manifest.publishedVersion
                $by = [string]$manifest.publishedBy
            }
            catch {
                $kind = '(unreadable manifest)'
            }
        }
        [void]$found.Add((New-Object psobject -Property @{
            Stamp            = $candidate.Name
            Path             = $candidate.FullName
            Kind             = $kind
            SnapshotVersion  = $replaced
            ReplacedByVersion = $published
            By               = $by
        }))
    }
    return $found.ToArray()
}

function Show-AvailableReleases {
    param($Releases)
    Write-Host 'AVAILABLE RELEASES (newest first)' -ForegroundColor Cyan
    Write-Host '  Each folder holds the code that was live immediately BEFORE that timestamp.'
    Write-Host ''
    if (-not $Releases -or $Releases.Count -eq 0) {
        Write-Host '  None. Nothing has been published to this destination yet.'
        return
    }
    foreach ($release in $Releases) {
        Write-Host ('  ' + $release.Stamp + '   holds v' + $release.SnapshotVersion + '   (was replaced by v' + $release.ReplacedByVersion + ', ' + $release.Kind + ')')
    }
    Write-Host ''
    Write-Host 'MATCHING DATA BACKUPS (only needed if the DATA is the problem)'
    $dataBackups = @()
    if (Test-Path -LiteralPath $backupsRoot -PathType Container) {
        $dataBackups = @(Get-ChildItem -LiteralPath $backupsRoot -Directory | Where-Object { $_.Name -like 'data-*' } | Sort-Object Name -Descending)
    }
    if ($dataBackups.Count -eq 0) {
        Write-Host '  None found.'
    }
    else {
        foreach ($backup in $dataBackups) {
            $stats = Get-TreeStats -Path $backup.FullName
            Write-Host ('  ' + $backup.Name + '   ' + $stats.Count + ' files, ' + (Format-Bytes $stats.Bytes))
        }
    }
    Write-Host ''
}

Write-Host ''
Write-Host '=== NWMS Quality Records - ROLLBACK ===' -ForegroundColor Yellow
Write-Host ("Destination : " + $destinationPath)
Write-Host ("Live URL    : " + $NetworkUrl)
if ($WhatIf) { Write-Host 'MODE        : WHAT-IF (nothing will be written)' -ForegroundColor Yellow }
Write-Host ''

$available = Get-AvailableReleases

if ($List) {
    Show-AvailableReleases -Releases $available
    Write-Host 'Pick one with:  -Release <stamp>     (omit it to use the most recent)'
    exit 0
}

if (-not (Test-Path -LiteralPath $releasesRoot -PathType Container)) {
    throw "No Releases folder at $releasesRoot -- has anything been published to this destination yet?"
}
if ($available.Count -eq 0) {
    throw "No release snapshots found in $releasesRoot. There is nothing to roll back to."
}

# ------------------------------------------------------------------------------
# 1. Work out which release
# ------------------------------------------------------------------------------
$target = $null
if ($Release) {
    foreach ($candidate in $available) {
        if ($candidate.Stamp -eq $Release) { $target = $candidate }
    }
    if ($null -eq $target) {
        Write-Host ("No release snapshot named '" + $Release + "' exists at this destination.") -ForegroundColor Red
        Write-Host ''
        Show-AvailableReleases -Releases $available
        throw "Unknown release: $Release"
    }
}
else {
    $target = $available[0]
    Write-Host ('No -Release given, using the most recent snapshot: ' + $target.Stamp)
    Write-Host ''
}

$snapshotDir = $target.Path
$snapshotStats = Get-TreeStats -Path $snapshotDir
if ($snapshotStats.Count -eq 0) {
    throw "Release snapshot $($target.Stamp) is empty: $snapshotDir. Nothing to restore -- pick another with -List."
}

# What is actually in the snapshot? Restore only what it holds; a snapshot taken
# on a first deployment legitimately has no web\ or scripts\ yet.
$snapshotFiles = New-Object System.Collections.ArrayList
foreach ($name in $apiFiles) {
    if (Test-Path -LiteralPath (Join-Path $snapshotDir $name)) { [void]$snapshotFiles.Add($name) }
}
$snapshotLaunchers = @(Get-ChildItem -LiteralPath $snapshotDir -File | Where-Object { $_.Extension -ieq '.cmd' })
foreach ($launcher in $snapshotLaunchers) { [void]$snapshotFiles.Add($launcher.Name) }

$snapshotFolders = New-Object System.Collections.ArrayList
foreach ($folderName in @('scripts', 'web')) {
    if (Test-Path -LiteralPath (Join-Path $snapshotDir $folderName) -PathType Container) { [void]$snapshotFolders.Add($folderName) }
}

if ($snapshotFolders -notcontains 'web') {
    Write-Warning "Snapshot $($target.Stamp) contains no web\ folder, so the front end will be left exactly as it is now. Only the service files will be rolled back. If the bad release was a front-end change, this rollback will not fix it -- check -List for an older snapshot."
}

$currentVersion = Get-ServiceVersion -ScriptPath (Join-Path $destinationPath 'qc-api.ps1')
$snapshotVersion = Get-ServiceVersion -ScriptPath (Join-Path $snapshotDir 'qc-api.ps1')

# ------------------------------------------------------------------------------
# 2. Refuse while the service is running
# ------------------------------------------------------------------------------
if (Test-ServiceLockHeld -LockFile $destinationLock) {
    throw @"
The Quality Records service is STILL RUNNING against $destinationData.

Its lock file is held right now:
  $destinationLock

Nothing has been changed. Stop it on NW-APPSERVER first: close its console
window, or find and stop the process.

Find it by COMMAND LINE, not by port. netstat / Get-NetTCPConnection report the
listening socket as owned by PID 4 ("System") because of http.sys, which tells
you nothing useful:

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
      Where-Object { `$_.CommandLine -like '*qc-api.ps1*' }

If it was started elevated you need an elevated session both to see its command
line and to stop it.
"@
}

# ------------------------------------------------------------------------------
# 3. The data decision
# ------------------------------------------------------------------------------
$dataBackupDir = ''
$dataBackupStats = New-Object psobject -Property @{ Count = 0; Bytes = 0 }
$currentDataStats = New-Object psobject -Property @{ Count = 0; Bytes = 0 }
if (Test-Path -LiteralPath $destinationData -PathType Container) {
    $currentDataStats = Get-TreeStats -Path $destinationData
}

if ($RestoreData) {
    $dataBackupDir = Join-Path $backupsRoot ('data-' + $target.Stamp)
    if (-not (Test-Path -LiteralPath $dataBackupDir -PathType Container)) {
        throw @"
-RestoreData was given, but there is no data backup for release $($target.Stamp):
  $dataBackupDir

Nothing has been changed. Run with -List to see which data backups exist, or
drop -RestoreData and roll back the CODE only (which is usually the right
answer anyway).
"@
    }
    $dataBackupStats = Get-TreeStats -Path $dataBackupDir
    if ($dataBackupStats.Count -eq 0) {
        throw "The data backup for release $($target.Stamp) is EMPTY: $dataBackupDir. Refusing to restore an empty data folder over live records."
    }
}

# ------------------------------------------------------------------------------
# 4. Show the plan
# ------------------------------------------------------------------------------
# The undo-snapshot stamp carries a "-rollback" suffix so it can NEVER collide
# with a release folder made by the publisher. Without it, a rollback run in the
# same clock second as the publish it is undoing -- i.e. the normal case, "that
# publish went wrong, roll it back now" -- resolves the undo snapshot to the very
# folder it is restoring FROM. It then copies the live (bad) files into that
# folder, restores them back out, and reports success naming the good version
# while the bad code is still deployed and the good snapshot is gone for ever.
$stamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss') + '-rollback'
$snapshotOfNowDir = Join-Path $releasesRoot $stamp
$preRollbackDataDir = Join-Path $backupsRoot ('data-' + $stamp)

# Belt and braces on top of the suffix: refuse rather than write into anything
# that already exists, and never let the two paths be the same folder.
if ($snapshotOfNowDir -ieq $snapshotDir) {
    throw "The undo snapshot would be the same folder as the release being restored ($snapshotDir). Refusing -- this would destroy the release you are rolling back to."
}
if (Test-Path -LiteralPath $snapshotOfNowDir) {
    throw "An undo snapshot folder for this second already exists: $snapshotOfNowDir. Wait a second and run again."
}
if (Test-Path -LiteralPath $preRollbackDataDir) {
    throw "A data backup folder for this second already exists: $preRollbackDataDir. Wait a second and run again."
}

Write-Host 'PLAN' -ForegroundColor Cyan
Write-Host ('  Roll back to release : ' + $target.Stamp)
Write-Host ('  Snapshot folder      : ' + $snapshotDir)
Write-Host ('  Snapshot contents    : ' + $snapshotStats.Count + ' files, ' + (Format-Bytes $snapshotStats.Bytes))
Write-Host ('  Code version         : ' + $currentVersion + '  ->  ' + $snapshotVersion)
Write-Host ('  Files to restore     : ' + (($snapshotFiles.ToArray()) -join ', '))
Write-Host ('  Folders to restore   : ' + (($snapshotFolders.ToArray()) -join ', '))
Write-Host ('  Undo snapshot        : ' + $snapshotOfNowDir + '   (so this rollback can itself be rolled back)')
Write-Host ''

if ($RestoreData) {
    Write-Host '  ###############################################################' -ForegroundColor Red
    Write-Host '  ###  -RestoreData IS SET. THIS DESTROYS WORK.               ###' -ForegroundColor Red
    Write-Host '  ###############################################################' -ForegroundColor Red
    Write-Host ''
    Write-Host ('  Live data now      : ' + $currentDataStats.Count + ' files, ' + (Format-Bytes $currentDataStats.Bytes)) -ForegroundColor Red
    Write-Host ('  Would be replaced  : ' + $dataBackupStats.Count + ' files, ' + (Format-Bytes $dataBackupStats.Bytes) + '  from ' + $dataBackupDir) -ForegroundColor Red
    Write-Host ''
    Write-Host '  Every quality record, sign-off and PHOTOGRAPH created since that backup' -ForegroundColor Red
    Write-Host '  was taken will be gone from data\. Photographic evidence cannot be' -ForegroundColor Red
    Write-Host '  retaken once the parts have shipped.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Restoring old CODE against current data is usually right.' -ForegroundColor Yellow
    Write-Host '  Restoring old DATA is almost never right. Only do this if the DATA' -ForegroundColor Yellow
    Write-Host '  itself is the problem -- not because a release was bad.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('  The data being overwritten will first be copied, and verified, to:')
    Write-Host ('    ' + $preRollbackDataDir)
    Write-Host ''
}
else {
    Write-Host '  data\ WILL NOT BE TOUCHED. Live records, data\attachments\ and' -ForegroundColor Green
    Write-Host '  data\settings.json stay exactly as they are. This is the right' -ForegroundColor Green
    Write-Host '  default: old code against current data is what a bad release needs.' -ForegroundColor Green
    Write-Host '  (Pass -RestoreData only if the DATA is the problem.)'
    Write-Host ''
}

if ($WhatIf) {
    Write-Host 'WHAT-IF: this is exactly what a real run would do:' -ForegroundColor Yellow
    Write-Host ('  1. Take the rollback lock        ' + $rollbackLockPath)
    Write-Host ('  2. Snapshot the code live NOW    -> ' + $snapshotOfNowDir + ' (+ manifest.json)')
    Write-Host ('  3. Restore files                 ' + (($snapshotFiles.ToArray()) -join ', ') + '  (hash-verified)')
    Write-Host ('  4. Mirror folders from the snapshot, verified by count and bytes:')
    foreach ($folderName in $snapshotFolders) {
        Write-Host ('       ' + $folderName + '\')
    }
    if ($RestoreData) {
        Write-Host ('  5. Copy live data\ aside         -> ' + $preRollbackDataDir + ', then VERIFY count+bytes')
        Write-Host ('  6. Replace data\                 from ' + $dataBackupDir)
        Write-Host '       (only after step 5 verifies -- otherwise it aborts before deleting anything)'
    }
    else {
        Write-Host '  5. data\                         NOT TOUCHED'
    }
    Write-Host ''
    Write-Host 'WHAT-IF complete. Nothing was written.' -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# 5. Typed confirmation for a data restore
# ------------------------------------------------------------------------------
if ($RestoreData) {
    # If there is no console to prompt on (a non-interactive session, a scheduled
    # task, a piped invocation) this must fail CLOSED. A data restore is never
    # something to let through just because nobody was there to be asked.
    $answer = ''
    try {
        $answer = Read-Host 'Type RESTORE DATA (in capitals) to overwrite live quality records, or anything else to abort'
    }
    catch {
        Write-Host ''
        Write-Host 'Aborted: there is no interactive console to confirm on.' -ForegroundColor Yellow
        Write-Host 'Nothing was changed -- not the code, not the data.'
        Write-Host 'A data restore is only ever done by hand, from a real PowerShell window.'
        exit 1
    }
    if ($answer -ne 'RESTORE DATA') {
        Write-Host ''
        Write-Host 'Aborted. Nothing was changed -- not the code, not the data.' -ForegroundColor Green
        Write-Host 'To roll back the CODE only, run the same command without -RestoreData.'
        exit 1
    }
    Write-Host ''
}

# ------------------------------------------------------------------------------
# 6. Do it
# ------------------------------------------------------------------------------
$rollbackLock = $null
try {
    Assert-SafeWriteTarget -Path $rollbackLockPath
    $rollbackLock = [IO.FileStream]::new($rollbackLockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    # --- 6a. Snapshot what is live right now, so the rollback is undoable -----
    Write-Host 'Snapshotting the currently live code (so this rollback can itself be undone)...' -ForegroundColor Cyan
    [void][IO.Directory]::CreateDirectory($releasesRoot)
    Assert-SafeWriteTarget -Path $snapshotOfNowDir -Allow $releasesRoot
    [void][IO.Directory]::CreateDirectory($snapshotOfNowDir)

    $savedFiles = New-Object System.Collections.ArrayList
    foreach ($name in $apiFiles) {
        $existing = Join-Path $destinationPath $name
        if (Test-Path -LiteralPath $existing) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $snapshotOfNowDir $name) -Force
            [void]$savedFiles.Add($name)
        }
    }
    $liveLaunchers = @(Get-ChildItem -LiteralPath $destinationPath -File | Where-Object { $_.Extension -ieq '.cmd' })
    foreach ($launcher in $liveLaunchers) {
        Copy-Item -LiteralPath $launcher.FullName -Destination (Join-Path $snapshotOfNowDir $launcher.Name) -Force
        [void]$savedFiles.Add($launcher.Name)
    }
    $savedFolders = New-Object System.Collections.ArrayList
    foreach ($folderName in @('scripts', 'web')) {
        $existingFolder = Join-Path $destinationPath $folderName
        if (Test-Path -LiteralPath $existingFolder -PathType Container) {
            Copy-Item -LiteralPath $existingFolder -Destination (Join-Path $snapshotOfNowDir $folderName) -Recurse -Force
            [void]$savedFolders.Add($folderName)
        }
    }
    $undoStats = Get-TreeStats -Path $snapshotOfNowDir
    Write-Host ('  ' + $undoStats.Count + ' files, ' + (Format-Bytes $undoStats.Bytes) + ' -> ' + $snapshotOfNowDir)

    # --- 6b. Restore the flat files (hash-verified) ---------------------------
    Write-Host ('Restoring code from release ' + $target.Stamp + '...') -ForegroundColor Cyan
    foreach ($name in $snapshotFiles) {
        $sourceFile = Join-Path $snapshotDir $name
        if (-not (Test-Path -LiteralPath $sourceFile)) { continue }
        $targetFile = Join-Path $destinationPath $name
        Assert-SafeWriteTarget -Path $targetFile
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw "Hash verification failed while restoring $name. Do NOT start the service; the code live before this rollback is in $snapshotOfNowDir." }
        Write-Host ('  ' + $name)
    }

    # --- 6c. Restore the folders (mirrored) -----------------------------------
    foreach ($folderName in $snapshotFolders) {
        $sourceFolder = Join-Path $snapshotDir $folderName
        $targetFolder = Join-Path $destinationPath $folderName
        Assert-SafeWriteTarget -Path $targetFolder
        if (Test-Path -LiteralPath $targetFolder) { Remove-Item -LiteralPath $targetFolder -Recurse -Force }
        Copy-Item -LiteralPath $sourceFolder -Destination $targetFolder -Recurse -Force
        $sourceStats = Get-TreeStats -Path $sourceFolder
        $targetStats = Get-TreeStats -Path $targetFolder
        if ($sourceStats.Count -ne $targetStats.Count -or $sourceStats.Bytes -ne $targetStats.Bytes) {
            throw "Restore verification failed for $folderName\ ($($sourceStats.Count) files/$($sourceStats.Bytes) bytes in the snapshot vs $($targetStats.Count)/$($targetStats.Bytes) restored). Do NOT start the service; the code live before this rollback is in $snapshotOfNowDir."
        }
        Write-Host ('  ' + $folderName + '\  (' + $targetStats.Count + ' files, mirrored, verified)')
    }

    if ($snapshotFolders -contains 'web') {
        if (-not (Test-Path -LiteralPath (Join-Path $destinationWeb 'index.html'))) {
            throw "web\index.html is missing after the restore -- the site would 404 on its own front page. The code live before this rollback is in $snapshotOfNowDir."
        }
    }

    # --- 6d. Data, only if explicitly asked for ------------------------------
    if ($RestoreData) {
        Write-Host ''
        Write-Host 'Restoring DATA (records, attachments, settings)...' -ForegroundColor Red

        # This block is the ONLY place in the whole deployment toolset that
        # writes inside data\, which is why Assert-SafeWriteTarget is not
        # applied to $destinationData here: -RestoreData plus a typed
        # confirmation is the sanctioned exception, and nothing else is.
        #
        # Copy the data being destroyed somewhere safe FIRST, and verify it,
        # before anything is deleted. If this verification fails the script
        # stops with live data still fully intact.
        [void][IO.Directory]::CreateDirectory($backupsRoot)
        Assert-SafeWriteTarget -Path $preRollbackDataDir -Allow $backupsRoot
        if (Test-Path -LiteralPath $destinationData -PathType Container) {
            Copy-Item -LiteralPath $destinationData -Destination $preRollbackDataDir -Recurse -Force
            $preStats = Get-TreeStats -Path $preRollbackDataDir
            if ($preStats.Count -ne $currentDataStats.Count -or $preStats.Bytes -ne $currentDataStats.Bytes) {
                throw @"
PRE-ROLLBACK DATA BACKUP VERIFICATION FAILED -- data has NOT been touched.

  live data : $($currentDataStats.Count) files, $($currentDataStats.Bytes) bytes
  copy      : $($preStats.Count) files, $($preStats.Bytes) bytes
  copy at   : $preRollbackDataDir

The code rollback above DID complete. The data was left alone because this
script will not delete records it cannot prove it copied first.
"@
            }
            Write-Host ('  Current data copied aside and verified: ' + $preRollbackDataDir)
            Write-Host ('    ' + $preStats.Count + ' files, ' + (Format-Bytes $preStats.Bytes))

            Remove-Item -LiteralPath $destinationData -Recurse -Force
        }

        Copy-Item -LiteralPath $dataBackupDir -Destination $destinationData -Recurse -Force
        $restoredStats = Get-TreeStats -Path $destinationData
        if ($restoredStats.Count -ne $dataBackupStats.Count -or $restoredStats.Bytes -ne $dataBackupStats.Bytes) {
            throw @"
DATA RESTORE VERIFICATION FAILED.

  backup   : $($dataBackupStats.Count) files, $($dataBackupStats.Bytes) bytes  ($dataBackupDir)
  restored : $($restoredStats.Count) files, $($restoredStats.Bytes) bytes  ($destinationData)

Do NOT start the service. The data as it was immediately before this rollback
is intact at:
  $preRollbackDataDir
Copy it back over data\ by hand, then work out what failed.
"@
        }
        Write-Host ('  Restored ' + $restoredStats.Count + ' files, ' + (Format-Bytes $restoredStats.Bytes) + ' from ' + $dataBackupDir) -ForegroundColor Red
        Write-Host '  Verified: file count and total bytes match.'
    }

    # --- 6e. Manifest for the undo snapshot ---------------------------------
    $manifest = [ordered]@{
        kind             = 'pre-rollback'
        stamp            = $stamp
        description      = 'Code that was live immediately BEFORE the rollback at this timestamp.'
        rolledBackAt     = [datetime]::Now.ToString('o')
        rolledBackBy     = "$env:USERDOMAIN\$env:USERNAME"
        sourceComputer   = $env:COMPUTERNAME
        rolledBackTo     = $target.Stamp
        publishedVersion = $snapshotVersion
        replacedVersion  = $currentVersion
        destination      = $destinationPath
        files            = @($savedFiles.ToArray())
        folders          = @($savedFolders.ToArray())
        savedFileCount   = $undoStats.Count
        savedBytes       = $undoStats.Bytes
        dataRestored     = [bool]$RestoreData
        dataBackupUsed   = $dataBackupDir
        dataBackup       = $preRollbackDataDir
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $snapshotOfNowDir 'manifest.json'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host ('Rolled back to release ' + $target.Stamp + ' (version ' + $snapshotVersion + ').') -ForegroundColor Green
    Write-Host ''
    Write-Host 'WRITTEN:'
    foreach ($name in $snapshotFiles) { Write-Host ('  ' + $name) }
    foreach ($folderName in $snapshotFolders) { Write-Host ('  ' + $folderName + '\  (mirrored)') }
    Write-Host ('  Releases\' + $stamp + '\   (the code that was live until a moment ago, + manifest.json)')
    if ($RestoreData) {
        Write-Host ('  data\                     RESTORED from ' + $dataBackupDir) -ForegroundColor Red
        Write-Host ('  Backups\data-' + $stamp + '\   (the data that was live until a moment ago)')
    }
    Write-Host ''
    if ($RestoreData) {
        Write-Host 'NOT TOUCHED: Backups\ and Releases\ apart from the folders listed above.'
    }
    else {
        Write-Host 'NOT TOUCHED:' -ForegroundColor Green
        Write-Host '  data\  -- live records, data\attachments\, data\settings.json are unchanged'
        Write-Host '  Backups\ and Releases\ apart from the one new folder above'
    }
    Write-Host ''
    Write-Host 'NEXT, BY HAND ON NW-APPSERVER (nothing is done remotely):' -ForegroundColor Cyan
    Write-Host '  1. Start the service: run "Start Quality Records Server.cmd" on NW-APPSERVER.'
    Write-Host ('  2. Check it came up : ' + $NetworkUrl + '/api/health')
    Write-Host ('     Expect version "' + $snapshotVersion + '".')
    Write-Host '  3. Open the app and confirm the Records list and the shared library look right.'
    Write-Host ''
    Write-Host ('To undo this rollback, run:  Rollback Quality Records.ps1 -Release ' + $stamp)
}
finally {
    if ($rollbackLock) { $rollbackLock.Dispose() }
    Remove-Item -LiteralPath $rollbackLockPath -Force -ErrorAction SilentlyContinue
}
