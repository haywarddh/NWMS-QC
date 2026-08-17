param(
    [string]$Destination = '\\NW-APPSERVER\NWMS_QC',
    [string]$NetworkUrl = 'http://nw-appserver:8791',
    [switch]$WhatIf
)

<#
================================================================================
 Publish Quality Records.ps1
================================================================================

 WHAT THIS DOES
 --------------
 Copies a tested local build of the NWMS Quality Records app to the network
 folder on NW-APPSERVER. Same shape, and the same safety rules, as
 "Publish Network Planner.ps1" in the Weekly Delivery Planner.

 It copies, in this order and nothing else:
   qc-api.ps1, README.md, CHANGELOG.md   (from ..\qc-api\)
   scripts\                              (mirrored -- this folder)
   *.cmd launchers                       (from the project root)
   ..\qc\dist\client\*  ->  web\         (mirrored)

 WHERE TO RUN IT
 ---------------
 On YOUR LAPTOP, from the LOCAL project folder. Never from the network copy.
 NOTHING is executed on NW-APPSERVER: a publish is a file copy to a UNC path.
 You stop and start the service on the server yourself, by hand, exactly as
 the deployment plan says. There is no WinRM/PSRemoting/PsExec anywhere in
 this estate and there must never be -- the laptop is deliberately non-domain
 to keep the blast radius small.

 WHAT IT REFUSES TO DO
 ---------------------
  1. Run from the network folder itself (that is how people overwrite the
     wrong thing).
  2. Publish without qc\dist\client\index.html -- the build would produce a
     site that 404s on its own front page.
  3. Publish a qc-api.ps1 that does not parse.
  4. Publish while the service is still running (data\qc-api.lock is held).
  5. Publish without a VERIFIED backup of the destination's data\ folder.
     A backup you did not verify is not a backup.
  6. Write ANYTHING inside data\, Backups\ or Releases\ other than the new
     backup folders it creates. data\ holds live quality records, the
     photographic evidence in data\attachments\ and the privileged password
     hash in data\settings.json. A lost photo cannot be retaken after the
     parts have shipped.

 -WhatIf prints every action, with real counts and real paths, and writes
 nothing at all. Use it for the first run against a new -Destination.
================================================================================
#>

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Paths. This script lives in scripts\; the release source is the project root
# one level up, same as the Planner.
# ------------------------------------------------------------------------------
$projectRoot     = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$scriptsSource   = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')

$sourceApiDir    = Join-Path $projectRoot 'qc-api'
$sourceApiScript = Join-Path $sourceApiDir 'qc-api.ps1'
$sourceWebRoot   = Join-Path $projectRoot 'qc\dist\client'

# Flat files taken from qc-api\ and dropped in the destination root.
$apiFiles = @('qc-api.ps1', 'README.md', 'CHANGELOG.md')

# .cmd launchers in the project root that are LOCAL ONLY and must never be
# published:
#   qc-dev.cmd                      starts the Vite dev server, needs Node --
#                                   which NW-APPSERVER does not have and does
#                                   not need.
#   Start Local Quality Records.cmd the laptop's localhost launcher. It points
#                                   at qc-api\qc-api.ps1 and qc\dist\client,
#                                   neither of which exists in the published
#                                   layout, so on the server it is nothing but
#                                   a confusing second Start icon.
# Everything else in the root ships, so a new launcher is published simply by
# existing -- no list to remember to update.
$localOnlyLaunchers = @('qc-dev.cmd', 'Start Local Quality Records.cmd')

# Folders at the destination this script must never write into. Checked
# programmatically before every single copy, not just trusted to be true.
$protectedFolders = @('data', 'Backups', 'Releases')

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# Count + total bytes of a folder tree. Used for every backup and every mirror,
# because "the copy finished without an error" and "the copy is complete" are
# not the same claim over a UNC path.
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

# Hard guard. Any destination path this script is about to write to is passed
# through here first. If it lands inside data\, Backups\ or Releases\ (other
# than a freshly created backup folder, which is passed with -Allow) the script
# stops before the write, not after it.
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

# The service lock is a REAL exclusive OS file lock held by qc-api.ps1 for its
# whole life (FileShare::None), not a flag file a crash could leave behind as a
# false positive. Opened here with FileMode::Open -- never OpenOrCreate -- so
# this test cannot itself create a file inside data\.
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

function Test-PowerShellSyntax {
    param([string]$ScriptPath)
    $text = Get-Content -LiteralPath $ScriptPath -Raw
    $null = [scriptblock]::Create($text)
}

Write-Host ''
Write-Host '=== NWMS Quality Records - Publish ===' -ForegroundColor Cyan
Write-Host ("Local source : " + $projectRoot)
Write-Host ("Destination  : " + $destinationPath)
Write-Host ("Live URL     : " + $NetworkUrl)
if ($WhatIf) { Write-Host 'MODE         : WHAT-IF (nothing will be written)' -ForegroundColor Yellow }
Write-Host ''

# ------------------------------------------------------------------------------
# 1. Refuse to run from the network folder itself
# ------------------------------------------------------------------------------
if ($projectRoot -ieq $destinationPath) {
    throw "Run the publisher from the LOCAL project folder, not from the network deployment folder ($destinationPath). Publishing the published copy over itself is how the wrong thing gets overwritten."
}
if ($scriptsSource.StartsWith($destinationPath + '\', 'OrdinalIgnoreCase')) {
    throw "This copy of the publisher is the one inside the network folder ($destinationPath). Run the copy in your LOCAL project folder instead."
}

# The two checks above only catch publishing a folder over ITSELF. This one
# catches the genuinely nasty variant: running the PUBLISHED copy of this script
# and pointing it at a DIFFERENT share -- e.g. Live's scripts\ folder aimed at
# Dev -- which would publish the server's own deployed files back out as if they
# were a fresh build. A published layout is recognisable: qc-api.ps1 and web\ in
# the root, and no qc-api\ or qc\ source folders.
$looksPublished = (Test-Path -LiteralPath (Join-Path $projectRoot 'qc-api.ps1')) -and
                  (Test-Path -LiteralPath (Join-Path $projectRoot 'web') -PathType Container) -and
                  (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'qc-api') -PathType Container))
if ($looksPublished) {
    throw "This copy of the publisher is sitting in a PUBLISHED deployment folder ($projectRoot -- it has qc-api.ps1 and web\ in the root, and no qc-api\ source folder). Publishing FROM a deployment folder would push the server's own deployed files out as if they were a fresh build. Run the publisher from your LOCAL project folder on the laptop instead."
}
if (-not (Test-Path -LiteralPath $destinationPath)) {
    throw "Network deployment folder is unavailable: $destinationPath. Check the share exists and you are on the LAN/VPN."
}

# ------------------------------------------------------------------------------
# 2. Validate the release BEFORE touching the destination
# ------------------------------------------------------------------------------
Write-Host 'Validating the local release...' -ForegroundColor Cyan

# --- The built front end ---
$sourceIndexHtml = Join-Path $sourceWebRoot 'index.html'
if (-not (Test-Path -LiteralPath $sourceIndexHtml)) {
    throw @"
Built front end is missing: $sourceIndexHtml

Without index.html the publish produces a site that 404s on its own front
page. Build it first:

    cd "$projectRoot\qc"
    npm run build

then confirm dist\client\index.html exists before publishing.
"@
}
if ((Get-Item -LiteralPath $sourceIndexHtml).Length -eq 0) {
    throw "Built front end is present but EMPTY: $sourceIndexHtml. Re-run 'npm run build' -- publishing this would produce a blank front page."
}

$sourceAssets = Join-Path $sourceWebRoot 'assets'
if (-not (Test-Path -LiteralPath $sourceAssets -PathType Container)) {
    throw "Built assets folder is missing: $sourceAssets. index.html without assets\ is an unstyled, non-functioning page. Re-run 'npm run build'."
}

# Fonts are self-hosted on purpose: NW-APPSERVER's LAN has no route out to
# fonts.googleapis.com, so a missing fonts\ folder means every page -- including
# a printed ISIR a customer reads -- silently falls back to system fonts.
$sourceFonts = Join-Path $sourceWebRoot 'fonts'
if (-not (Test-Path -LiteralPath $sourceFonts -PathType Container)) {
    throw "Self-hosted fonts folder is missing: $sourceFonts. The LAN has no route to fonts.googleapis.com, so without this every page falls back to system fonts. Check qc\public\fonts\ survived the build, then re-run 'npm run build'."
}
$fontFileCount = @(Get-ChildItem -LiteralPath $sourceFonts -Recurse -File | Where-Object { $_.Extension -ieq '.woff2' }).Count
if ($fontFileCount -eq 0) {
    throw "Fonts folder exists but contains no .woff2 files: $sourceFonts. Run qc\scripts\fetch-fonts.ps1 to regenerate them."
}

# --- The service ---
if (-not (Test-Path -LiteralPath $sourceApiScript)) {
    throw "Service script is missing: $sourceApiScript"
}
foreach ($name in $apiFiles) {
    $path = Join-Path $sourceApiDir $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Required release file is missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -eq 0) { throw "Release file is empty: $path" }
}

try {
    Test-PowerShellSyntax -ScriptPath $sourceApiScript
}
catch {
    throw ("qc-api.ps1 does not parse -- publishing it would leave a service that cannot start: " + $_.Exception.Message)
}

# Every .ps1 in scripts\ ships to the server too, so every one of them gets the
# same parse check. A broken Configure/Publish script on the server is a bad
# afternoon at exactly the wrong moment.
$scriptFiles = @(Get-ChildItem -LiteralPath $scriptsSource -File | Where-Object { $_.Extension -ieq '.ps1' } | Sort-Object Name)
foreach ($scriptFile in $scriptFiles) {
    try {
        Test-PowerShellSyntax -ScriptPath $scriptFile.FullName
    }
    catch {
        throw ("PowerShell validation failed for scripts\" + $scriptFile.Name + ": " + $_.Exception.Message)
    }
}

# --- The launchers ---
$launcherFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -File |
        Where-Object { $_.Extension -ieq '.cmd' -and $localOnlyLaunchers -notcontains $_.Name } |
        Sort-Object Name
)
$startLauncher = 'Start Quality Records Server.cmd'
$hasStartLauncher = $false
foreach ($launcher in $launcherFiles) {
    if ($launcher.Name -ieq $startLauncher) { $hasStartLauncher = $true }
}
if (-not $hasStartLauncher) {
    Write-Warning "'$startLauncher' was not found in $projectRoot. Without it there is nothing to double-click on NW-APPSERVER to start the service. Publishing anyway -- the service can still be started by hand -- but write that launcher."
}

$configureScript = Join-Path $scriptsSource 'Configure Quality Records.ps1'
if (-not (Test-Path -LiteralPath $configureScript)) {
    Write-Warning "'Configure Quality Records.ps1' is not in scripts\ yet. First-time setup on NW-APPSERVER (urlacl + Domain-profile firewall rule) then has to be done by hand from the deployment plan."
}

$publishVersion = Get-ServiceVersion -ScriptPath $sourceApiScript
$currentVersion = Get-ServiceVersion -ScriptPath (Join-Path $destinationPath 'qc-api.ps1')

# ONE version covers the whole deployment, so the two places that carry it must
# agree BEFORE anything is copied. They are published together and a tester only
# ever reports one number: if the front end says 0.5.0 while the service says
# 0.4.1, that number identifies nothing and every "which build?" answer after it
# is a guess. Checked here rather than trusted, because the two files are edited
# by hand and nothing else would notice.
$appVersionFile = Join-Path $projectRoot 'qc\src\lib\version.ts'
if (-not (Test-Path -LiteralPath $appVersionFile)) {
    throw "Cannot find the app version file: $appVersionFile. It is the front end's half of the version and the publisher will not guess it."
}
$appVersionMatch = [regex]::Match((Get-Content -LiteralPath $appVersionFile -Raw), 'APP_VERSION\s*=\s*"([^"]+)"')
if (-not $appVersionMatch.Success) {
    throw "Could not read APP_VERSION from $appVersionFile."
}
$appVersion = $appVersionMatch.Groups[1].Value
if ($appVersion -ne $publishVersion) {
    throw @"
VERSION MISMATCH -- nothing has been published.

  front end (qc\src\lib\version.ts)  APP_VERSION     = $appVersion
  service   (qc-api\qc-api.ps1)      `$ServiceVersion = $publishVersion

These are published together and are reported as ONE version, so they must
match. Bump both, add the CHANGELOG.md entry, rebuild the front end
(npm run build -- the version is compiled into the bundle), then publish again.
"@
}

$webStats     = Get-TreeStats -Path $sourceWebRoot
$scriptsStats = Get-TreeStats -Path $scriptsSource

Write-Host '  index.html            OK'
Write-Host ('  assets\, fonts\       OK (' + $fontFileCount + ' woff2 files)')
Write-Host ('  qc-api.ps1 parses     OK (version ' + $publishVersion + ')')
Write-Host ('  version files agree   OK (front end and service both ' + $appVersion + ')')
Write-Host ('  scripts\*.ps1 parse   OK (' + $scriptFiles.Count + ' scripts)')
Write-Host ('  launchers             ' + $launcherFiles.Count + ' .cmd file(s)')
Write-Host ''
Write-Host 'VERSION' -ForegroundColor Cyan
Write-Host ('  currently published : ' + $currentVersion)
Write-Host ('  about to publish    : ' + $publishVersion)
if ($currentVersion -eq $publishVersion) {
    Write-Warning "The destination already reports version $publishVersion. If this is a real change, bump `$ServiceVersion in qc-api.ps1 and add a CHANGELOG.md entry first -- a deployed build whose version you cannot identify is the thing that wastes an afternoon later."
}
Write-Host ''

# ------------------------------------------------------------------------------
# 3. Refuse if the service is still running
# ------------------------------------------------------------------------------
$destinationData = Join-Path $destinationPath 'data'
$destinationLock = Join-Path $destinationData 'qc-api.lock'

if (Test-ServiceLockHeld -LockFile $destinationLock) {
    throw @"
The Quality Records service is STILL RUNNING against $destinationData.

Its lock file is held right now:
  $destinationLock

Publishing over a running service would replace qc-api.ps1 and web\ underneath
it, so nothing has been changed. Stop it on NW-APPSERVER first: close its
console window, or find and stop the process.

Find it by COMMAND LINE, not by port. netstat / Get-NetTCPConnection report the
listening socket as owned by PID 4 ("System") because of http.sys, which tells
you nothing useful:

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
      Where-Object { `$_.CommandLine -like '*qc-api.ps1*' }

If it was started elevated you need an elevated session both to see its command
line and to stop it.
"@
}

if (Test-Path -LiteralPath $destinationLock) {
    Write-Host 'Service lock file exists but is NOT held -- a leftover from a hard kill, not a running service.' -ForegroundColor Yellow
    try {
        $lockStamp = (Get-Content -LiteralPath $destinationLock -Raw).Trim()
        if ($lockStamp) {
            foreach ($line in ($lockStamp -split "`r?`n")) { Write-Host ('    ' + $line) }
        }
    }
    catch { }
    Write-Host '  Left in place on purpose: it lives inside data\, this script never writes there,'
    Write-Host '  and qc-api.ps1 opens it OpenOrCreate so a stale one is harmless.'
    Write-Host ''
}
else {
    Write-Host 'Service is not running (no lock held) -- safe to publish.' -ForegroundColor Green
    Write-Host ''
}

# ------------------------------------------------------------------------------
# 4. Work out the plan
# ------------------------------------------------------------------------------
$stamp             = [datetime]::Now.ToString('yyyyMMdd-HHmmss')
$backupsRoot       = Join-Path $destinationPath 'Backups'
$releasesRoot      = Join-Path $destinationPath 'Releases'
$dataBackupDir     = Join-Path $backupsRoot ('data-' + $stamp)
$releaseDir        = Join-Path $releasesRoot $stamp
$destinationWeb    = Join-Path $destinationPath 'web'
$destinationScripts = Join-Path $destinationPath 'scripts'
$publishLockPath   = Join-Path $destinationPath '.publish.lock'

# Never write into an archive folder that already exists. Copy-Item -Recurse into
# an existing folder NESTS (web\web\), so a second-granularity stamp collision --
# most likely against a rollback's own undo snapshot -- would silently corrupt the
# archive. The live data and the publish itself would be fine; what breaks is the
# rollback source, discovered only when someone needs it.
if (Test-Path -LiteralPath $releaseDir) {
    throw "A release folder for this second already exists: $releaseDir. Wait a second and run again."
}
if (Test-Path -LiteralPath $dataBackupDir) {
    throw "A data backup folder for this second already exists: $dataBackupDir. Wait a second and run again."
}

$dataExists = Test-Path -LiteralPath $destinationData -PathType Container
$dataStats = New-Object psobject -Property @{ Count = 0; Bytes = 0 }
if ($dataExists) { $dataStats = Get-TreeStats -Path $destinationData }

$looksLikeFirstDeployment = (-not $dataExists) -and (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'qc-api.ps1')))
if ($looksLikeFirstDeployment) {
    Write-Host 'FIRST DEPLOYMENT: this destination has no qc-api.ps1 and no data\ folder.' -ForegroundColor Yellow
    Write-Host '  Nothing to back up. The service creates data\ (empty) on its first start.'
    Write-Host '  If you did NOT expect a first deployment, STOP and check -Destination is right.'
    Write-Host ''
}
elseif (-not $dataExists) {
    Write-Warning "The destination has application files but NO data\ folder ($destinationData). That is unusual on an established install -- check you have the right -Destination before continuing. Nothing to back up."
}

# ------------------------------------------------------------------------------
# 5. -WhatIf: print the whole plan, write nothing
# ------------------------------------------------------------------------------
if ($WhatIf) {
    Write-Host 'WHAT-IF: validation passed. This is exactly what a real run would do:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('  1. Take the publish lock       ' + $publishLockPath)
    if ($dataExists) {
        Write-Host ('  2. BACK UP live data           ' + $destinationData)
        Write-Host ('       -> ' + $dataBackupDir)
        Write-Host ('       ' + $dataStats.Count + ' files, ' + (Format-Bytes $dataStats.Bytes) + ' (includes attachments\ and settings.json)')
        Write-Host '       then verify file count and total bytes match, and abort if they do not'
    }
    else {
        Write-Host '  2. BACK UP live data           SKIPPED - no data\ folder at the destination yet'
    }
    Write-Host ('  3. BACK UP current code        -> ' + $releaseDir)
    Write-Host ('       qc-api.ps1 + README.md + CHANGELOG.md + *.cmd + scripts\ + web\, plus manifest.json')
    Write-Host ('  4. COPY qc-api\ flat files     ' + ($apiFiles -join ', ') + '  (hash-verified)')
    Write-Host ('  5. COPY ' + $launcherFiles.Count + ' launcher .cmd file(s)  (hash-verified)')
    foreach ($launcher in $launcherFiles) {
        Write-Host ('       ' + $launcher.Name)
    }
    Write-Host ('  6. MIRROR scripts\             ' + $scriptsStats.Count + ' files, ' + (Format-Bytes $scriptsStats.Bytes))
    Write-Host ('       -> ' + $destinationScripts + '  (deletes files no longer in the local scripts\)')
    Write-Host ('  7. MIRROR the front end        ' + $sourceWebRoot)
    Write-Host ('       -> ' + $destinationWeb)
    Write-Host ('       ' + $webStats.Count + ' files, ' + (Format-Bytes $webStats.Bytes) + '  (deletes stale hashed assets)')
    Write-Host ''
    Write-Host '  NOT TOUCHED, at all:' -ForegroundColor Green
    Write-Host ('    ' + $destinationData + '      (live records, attachments\, settings.json)')
    Write-Host ('    ' + $backupsRoot + '   (except the one new folder above)')
    Write-Host ('    ' + $releasesRoot + '  (except the one new folder above)')
    Write-Host ''
    Write-Host ('  Version would go ' + $currentVersion + ' -> ' + $publishVersion)
    Write-Host ''
    Write-Host 'WHAT-IF complete. Nothing was written. Re-run without -WhatIf to publish.' -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# 6. Do it
# ------------------------------------------------------------------------------
$publishLock = $null
try {
    Assert-SafeWriteTarget -Path $publishLockPath
    $publishLock = [IO.FileStream]::new($publishLockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    # --- 6a. Back up the live data folder, and VERIFY it ----------------------
    $dataBackupStats = New-Object psobject -Property @{ Count = 0; Bytes = 0 }
    if ($dataExists) {
        Write-Host 'Backing up live data (records, attachments, settings)...' -ForegroundColor Cyan
        [void][IO.Directory]::CreateDirectory($backupsRoot)
        Assert-SafeWriteTarget -Path $dataBackupDir -Allow $backupsRoot
        # Deliberately NOT pre-created: Copy-Item on a folder whose destination
        # does not exist creates the destination AS the copy. Pre-creating it
        # would instead nest the copy as Backups\data-<stamp>\data\.
        Copy-Item -LiteralPath $destinationData -Destination $dataBackupDir -Recurse -Force

        $dataBackupStats = Get-TreeStats -Path $dataBackupDir
        if ($dataBackupStats.Count -ne $dataStats.Count -or $dataBackupStats.Bytes -ne $dataStats.Bytes) {
            throw @"
DATA BACKUP VERIFICATION FAILED -- nothing has been published.

  live data : $($dataStats.Count) files, $($dataStats.Bytes) bytes
  backup    : $($dataBackupStats.Count) files, $($dataBackupStats.Bytes) bytes
  backup at : $dataBackupDir

A backup you did not verify is not a backup, so this stops here rather than
publishing over records and photographs it cannot prove it saved. The live
data\ folder has NOT been altered. Check free space and share permissions on
the destination, delete the failed backup folder, and try again.
"@
        }
        Write-Host ('  ' + $dataBackupStats.Count + ' files, ' + (Format-Bytes $dataBackupStats.Bytes) + ' -> ' + $dataBackupDir)
        Write-Host '  Verified: file count and total bytes match.' -ForegroundColor Green
    }

    # --- 6b. Back up the code that is live right now --------------------------
    Write-Host 'Backing up the currently published code...' -ForegroundColor Cyan
    [void][IO.Directory]::CreateDirectory($releasesRoot)
    Assert-SafeWriteTarget -Path $releaseDir -Allow $releasesRoot
    [void][IO.Directory]::CreateDirectory($releaseDir)

    $savedFiles = New-Object System.Collections.ArrayList
    foreach ($name in $apiFiles) {
        $existing = Join-Path $destinationPath $name
        if (Test-Path -LiteralPath $existing) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $releaseDir $name) -Force
            [void]$savedFiles.Add($name)
        }
    }
    $destinationLaunchers = @(Get-ChildItem -LiteralPath $destinationPath -File | Where-Object { $_.Extension -ieq '.cmd' })
    foreach ($launcher in $destinationLaunchers) {
        Copy-Item -LiteralPath $launcher.FullName -Destination (Join-Path $releaseDir $launcher.Name) -Force
        [void]$savedFiles.Add($launcher.Name)
    }
    $savedFolders = New-Object System.Collections.ArrayList
    foreach ($folderName in @('scripts', 'web')) {
        $existingFolder = Join-Path $destinationPath $folderName
        if (Test-Path -LiteralPath $existingFolder -PathType Container) {
            Copy-Item -LiteralPath $existingFolder -Destination (Join-Path $releaseDir $folderName) -Recurse -Force
            [void]$savedFolders.Add($folderName)
        }
    }
    $releaseStats = Get-TreeStats -Path $releaseDir
    Write-Host ('  ' + $releaseStats.Count + ' files, ' + (Format-Bytes $releaseStats.Bytes) + ' -> ' + $releaseDir)

    # --- 6c. Publish the flat files (hash-verified) ---------------------------
    Write-Host 'Publishing the service and documentation...' -ForegroundColor Cyan
    foreach ($name in $apiFiles) {
        $sourceFile = Join-Path $sourceApiDir $name
        $targetFile = Join-Path $destinationPath $name
        Assert-SafeWriteTarget -Path $targetFile
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw "Hash verification failed after publishing $name. The destination copy does not match the source -- do NOT start the service; roll back with 'Rollback Quality Records.ps1'." }
        Write-Host ('  ' + $name)
    }

    foreach ($launcher in $launcherFiles) {
        $targetFile = Join-Path $destinationPath $launcher.Name
        Assert-SafeWriteTarget -Path $targetFile
        Copy-Item -LiteralPath $launcher.FullName -Destination $targetFile -Force
        $sourceHash = (Get-FileHash -LiteralPath $launcher.FullName -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw ("Hash verification failed after publishing " + $launcher.Name) }
        Write-Host ('  ' + $launcher.Name)
    }

    # --- 6d. Mirror scripts\ --------------------------------------------------
    # Mirror rather than merge: a script deleted or renamed locally must not
    # linger on the server forever.
    Write-Host 'Mirroring scripts\ (removing anything no longer in the local folder)...' -ForegroundColor Cyan
    Assert-SafeWriteTarget -Path $destinationScripts
    if (Test-Path -LiteralPath $destinationScripts) { Remove-Item -LiteralPath $destinationScripts -Recurse -Force }
    Copy-Item -LiteralPath $scriptsSource -Destination $destinationScripts -Recurse -Force
    $publishedScriptsStats = Get-TreeStats -Path $destinationScripts
    if ($publishedScriptsStats.Count -ne $scriptsStats.Count -or $publishedScriptsStats.Bytes -ne $scriptsStats.Bytes) {
        throw "scripts\ mirror verification failed ($($scriptsStats.Count) files/$($scriptsStats.Bytes) bytes local vs $($publishedScriptsStats.Count)/$($publishedScriptsStats.Bytes) published). The previous scripts\ is in $releaseDir\scripts."
    }
    Write-Host ('  ' + $publishedScriptsStats.Count + ' files, verified.') -ForegroundColor Green

    # --- 6e. Mirror the front end into web\ ----------------------------------
    # Also a mirror, and for a concrete reason: Vite writes content-hashed
    # asset names, so a merge would accumulate every asset from every build
    # ever published and never drop one.
    Write-Host 'Mirroring the front end into web\ (removing stale hashed assets)...' -ForegroundColor Cyan
    Assert-SafeWriteTarget -Path $destinationWeb
    if (Test-Path -LiteralPath $destinationWeb) { Remove-Item -LiteralPath $destinationWeb -Recurse -Force }
    # dist\client\ becomes web\ -- Copy-Item renames the tree when the
    # destination folder does not exist, so it must NOT be pre-created.
    Copy-Item -LiteralPath $sourceWebRoot -Destination $destinationWeb -Recurse -Force
    $publishedWebStats = Get-TreeStats -Path $destinationWeb
    if ($publishedWebStats.Count -ne $webStats.Count -or $publishedWebStats.Bytes -ne $webStats.Bytes) {
        throw "web\ mirror verification failed ($($webStats.Count) files/$($webStats.Bytes) bytes local vs $($publishedWebStats.Count)/$($publishedWebStats.Bytes) published). Do NOT start the service; the previous web\ is in $releaseDir\web."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destinationWeb 'index.html'))) {
        throw "web\index.html is missing after the mirror -- the site would 404 on its own front page. Roll back with 'Rollback Quality Records.ps1'."
    }
    Write-Host ('  ' + $publishedWebStats.Count + ' files, ' + (Format-Bytes $publishedWebStats.Bytes) + ', index.html present, verified.') -ForegroundColor Green

    # --- 6f. Manifest --------------------------------------------------------
    # Written last, so its presence means the publish actually completed. The
    # rollback script reads this.
    $manifest = [ordered]@{
        kind                 = 'pre-publish'
        stamp                = $stamp
        description          = 'Code that was live immediately BEFORE the publish at this timestamp.'
        publishedAt          = [datetime]::Now.ToString('o')
        publishedBy          = "$env:USERDOMAIN\$env:USERNAME"
        sourceComputer       = $env:COMPUTERNAME
        publishedVersion     = $publishVersion
        replacedVersion      = $currentVersion
        destination          = $destinationPath
        sourceProject        = $projectRoot
        sourceWebRoot        = $sourceWebRoot
        sourceApiScript      = $sourceApiScript
        files                = @($savedFiles.ToArray())
        folders              = @($savedFolders.ToArray())
        savedFileCount       = $releaseStats.Count
        savedBytes           = $releaseStats.Bytes
        publishedWebFiles    = $publishedWebStats.Count
        publishedWebBytes    = $publishedWebStats.Bytes
        dataBackup           = $dataBackupDir
        dataBackupFileCount  = $dataBackupStats.Count
        dataBackupBytes      = $dataBackupStats.Bytes
        dataPreserved        = $true
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $releaseDir 'manifest.json'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host ('Published version ' + $publishVersion + ' successfully (release ' + $stamp + ').') -ForegroundColor Green
    Write-Host ''
    Write-Host 'WRITTEN:'
    Write-Host ('  ' + ($apiFiles -join ', '))
    Write-Host ('  ' + $launcherFiles.Count + ' launcher .cmd file(s)')
    Write-Host ('  scripts\  (' + $publishedScriptsStats.Count + ' files, mirrored)')
    Write-Host ('  web\      (' + $publishedWebStats.Count + ' files, mirrored)')
    if ($dataExists) {
        Write-Host ('  Backups\data-' + $stamp + '\   (verified data backup, ' + $dataBackupStats.Count + ' files)')
    }
    Write-Host ('  Releases\' + $stamp + '\       (previous code + manifest.json)')
    Write-Host ''
    Write-Host 'NOT TOUCHED:' -ForegroundColor Green
    if ($dataExists) {
        Write-Host ('  data\  -- live records, data\attachments\ photographic evidence, data\settings.json')
    }
    else {
        Write-Host ('  data\  -- does not exist yet; the service creates it, empty, on its first start')
    }
    Write-Host ('  Backups\ and Releases\ apart from the new folder(s) above')
    Write-Host ''
    Write-Host 'NEXT, BY HAND ON NW-APPSERVER (nothing is done remotely):' -ForegroundColor Cyan
    # Name the launcher that matches THIS destination. Both are published to both
    # shares and each refuses to run from the wrong one, so telling someone to run
    # the Live launcher after a Dev publish sends them into a refusal message.
    $isDevShare = $destinationPath -match '_Dev\\?$'
    if ($isDevShare) {
        Write-Host '  1. Start the service: run "Start Quality Records Dev Server.cmd" on NW-APPSERVER.'
        Write-Host '     (the LIVE launcher in this folder will refuse -- it would serve Dev data on Live''s port)'
    }
    else {
        Write-Host '  1. Start the service: run "Start Quality Records Server.cmd" on NW-APPSERVER.'
    }
    Write-Host ('  2. Check it came up : ' + $NetworkUrl + '/api/health')
    Write-Host ('     Expect version "' + $publishVersion + '" and the instance label you started it with.')
    Write-Host '  3. Open the app and confirm the Records list and the shared library are intact.'
    Write-Host ''
    Write-Host ('  App URL: ' + $NetworkUrl + '/')
    Write-Host ''
    Write-Host 'If it does not come up, or /api/health times out with no reply at all: check the'
    Write-Host 'firewall rule is on the DOMAIN profile and that Get-NetConnectionProfile says the'
    Write-Host 'active network really is Domain. A Private/Public classification makes the rule'
    Write-Host 'silently never match, and connections are DROPPED rather than refused -- which'
    Write-Host 'looks exactly like a timeout, not like a firewall problem.'
}
finally {
    if ($publishLock) { $publishLock.Dispose() }
    Remove-Item -LiteralPath $publishLockPath -Force -ErrorAction SilentlyContinue
}
