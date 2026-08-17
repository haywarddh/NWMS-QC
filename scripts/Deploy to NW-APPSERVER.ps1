param(
    [string]$Destination = '\\NW-APPSERVER\NWMS_QC',
    [string]$NetworkUrl = 'http://nw-appserver:8791',
    [switch]$WhatIf
)

<#
================================================================================
 Deploy to NW-APPSERVER.ps1
================================================================================

 WHAT THIS DOES
 --------------
 The day-to-day wrapper. Three steps, in order, with a pause where a human is
 needed:

   1. Check whether the live service still holds the data lock, and if it does,
      tell you how to stop it and wait for you to do it.
   2. Run "Publish Quality Records.ps1" -- which does all the real validating,
      backing up and verifying. Nothing is duplicated here.
   3. Wait for /api/health to answer after you have STARTED the service
      yourself, and print the version and instance label it reports.

 WHAT IT DOES NOT DO, ON PURPOSE
 -------------------------------
 It never touches NW-APPSERVER remotely. No WinRM, no PSRemoting, no
 Invoke-Command, no PsExec, no remote scheduled task. This laptop is
 deliberately non-domain so that the blast radius of a mistake stays small,
 and that only holds if a publish really is nothing more than a file copy to a
 UNC path.

 So it cannot start or stop the service for you. It asks, waits, and then
 checks -- which is exactly what the Planner's equivalent does.

 WHERE TO RUN IT
 ---------------
 On YOUR LAPTOP, from the LOCAL project folder (double-click
 "Deploy to NW-APPSERVER.cmd" in the project root).

 -WhatIf passes straight through to the publisher: it validates everything and
 writes nothing. Use it before the first real run against a new -Destination.
================================================================================
#>

$ErrorActionPreference = 'Stop'
$scriptsRoot = $PSScriptRoot

$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$destinationData = Join-Path $destinationPath 'data'
$destinationLock = Join-Path $destinationData 'qc-api.lock'
$healthUrl = ($NetworkUrl.TrimEnd('/')) + '/api/health'

# Pulled out of -NetworkUrl rather than hardcoded, so the localhost hint printed
# in the troubleshooting block below is right for a Dev instance (8792) too.
$portMatch = [regex]::Match($NetworkUrl, ':(\d+)')
$port = '8791'
if ($portMatch.Success) { $port = $portMatch.Groups[1].Value }
$localHealthUrl = 'http://localhost:' + $port + '/api/health'

# The service lock is a REAL exclusive OS file lock held by qc-api.ps1 for its
# whole life (FileShare::None). Opened with FileMode::Open -- never OpenOrCreate
# -- so this test cannot itself create a file inside data\.
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

function Get-ServiceHealth {
    try {
        $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 3
        if ($health.ok) { return $health }
    }
    catch { }
    return $null
}

function Show-HowToStopTheService {
    Write-Host ''
    Write-Host 'To stop it, ON NW-APPSERVER:' -ForegroundColor Yellow
    Write-Host '  Close the "NWMS Quality Records" console window, or find the process and stop it.'
    Write-Host ''
    Write-Host '  Find it by COMMAND LINE, not by port. netstat / Get-NetTCPConnection report the'
    Write-Host '  listening socket as owned by PID 4 ("System") because of http.sys, which tells'
    Write-Host '  you nothing useful:'
    Write-Host ''
    Write-Host '      Get-CimInstance Win32_Process -Filter "Name=''powershell.exe''" |'
    Write-Host '        Where-Object { $_.CommandLine -like ''*qc-api.ps1*'' }'
    Write-Host ''
    Write-Host '  If it was started elevated you need an elevated session both to see its'
    Write-Host '  command line and to stop it.'
    Write-Host ''
}

Write-Host ''
Write-Host '=== NWMS Quality Records - Deploy to NW-APPSERVER ===' -ForegroundColor Cyan
Write-Host ("Network folder : " + $destinationPath)
Write-Host ("Live URL       : " + $NetworkUrl + '/')
Write-Host ("Health         : " + $healthUrl)
if ($WhatIf) { Write-Host 'MODE           : WHAT-IF (nothing will be written)' -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Nothing is executed on NW-APPSERVER. This copies files to the share and then'
Write-Host 'waits for you to start the service there by hand.'
Write-Host ''

if (-not (Test-Path -LiteralPath $destinationPath)) {
    throw "Network deployment folder is unavailable: $destinationPath. Check the share exists and you are on the LAN/VPN."
}

# --- 1. Make sure the service is stopped before publishing --------------------
Write-Host '--- Step 1 of 3: is the live service stopped? ---' -ForegroundColor Cyan

$health = Get-ServiceHealth
$lockHeld = Test-ServiceLockHeld -LockFile $destinationLock

if ($lockHeld -or $health) {
    if ($health) {
        Write-Host ('The live service is RUNNING: version ' + $health.version + ', instance "' + $health.instance + '", ' + $health.plans + ' plans.') -ForegroundColor Yellow
    }
    if ($lockHeld) {
        Write-Host ('It holds the data lock: ' + $destinationLock) -ForegroundColor Yellow
    }
    Write-Host 'It must be stopped before publishing, or the publish would replace qc-api.ps1'
    Write-Host 'and web\ underneath a running service.'
    Show-HowToStopTheService

    if ($WhatIf) {
        Write-Host 'WHAT-IF: not waiting. The publisher below would refuse while the lock is held.' -ForegroundColor Yellow
        Write-Host ''
    }
    else {
        Read-Host 'Press Enter once the service is stopped'

        $lockHeld = Test-ServiceLockHeld -LockFile $destinationLock
        $health = Get-ServiceHealth
        if ($lockHeld -or $health) {
            Write-Host ''
            Write-Host 'The service still looks live, so stopping here.' -ForegroundColor Red
            if ($lockHeld) { Write-Host ('  The data lock is still held: ' + $destinationLock) }
            if ($health) { Write-Host ('  ' + $healthUrl + ' is still answering.') }
            Write-Host ''
            Write-Host 'Nothing has been published. The publisher would have refused anyway -- this'
            Write-Host 'just says so before doing any work.'
            exit 1
        }
        Write-Host 'Service is stopped.' -ForegroundColor Green
        Write-Host ''
    }
}
else {
    Write-Host 'Service is not running (no lock held, health not answering) -- safe to publish.' -ForegroundColor Green
    Write-Host ''
}

# --- 2. Publish ---------------------------------------------------------------
Write-Host '--- Step 2 of 3: publish ---' -ForegroundColor Cyan
Write-Host 'Validation, the verified data\ backup, the previous-code snapshot and the'
Write-Host 'hash-verified copy are all the publisher''s job, not this script''s.'
Write-Host ''

$publisher = Join-Path $scriptsRoot 'Publish Quality Records.ps1'
if (-not (Test-Path -LiteralPath $publisher)) {
    throw "Publisher not found: $publisher"
}

$global:LASTEXITCODE = 0
try {
    if ($WhatIf) {
        & $publisher -Destination $destinationPath -NetworkUrl $NetworkUrl -WhatIf
    }
    else {
        & $publisher -Destination $destinationPath -NetworkUrl $NetworkUrl
    }
}
catch {
    Write-Host ''
    Write-Host 'PUBLISH FAILED -- see the message above.' -ForegroundColor Red
    Write-Host ($_.Exception.Message)
    Write-Host ''
    Write-Host 'Nothing has been started. If the failure happened part-way through a copy, roll'
    Write-Host 'back with:  scripts\Rollback Quality Records.ps1'
    exit 1
}
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host ('PUBLISH FAILED (exit code ' + $LASTEXITCODE + ') -- see the messages above. The service has not been started.') -ForegroundColor Red
    exit 1
}

if ($WhatIf) {
    Write-Host ''
    Write-Host 'WHAT-IF complete. Nothing was written and nothing needs starting.' -ForegroundColor Yellow
    exit 0
}

# --- 3. Wait for Dave to start it, then confirm -------------------------------
Write-Host ''
Write-Host '--- Step 3 of 3: start it on NW-APPSERVER, then this will confirm ---' -ForegroundColor Cyan
Write-Host ''
Write-Host '  ON NW-APPSERVER, run "Start Quality Records Server.cmd".' -ForegroundColor Yellow
Write-Host ''
Write-Host ('Waiting for ' + $healthUrl + ' (checking every 3s for up to 60s)...')

$deadline = (Get-Date).AddSeconds(60)
$healthy = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $healthy = Get-ServiceHealth
    if ($healthy) { break }
    Write-Host '.' -NoNewline
}
Write-Host ''

if ($healthy) {
    Write-Host ''
    Write-Host 'Deployment complete.' -ForegroundColor Green
    Write-Host ('  URL      : ' + $NetworkUrl + '/')
    Write-Host ('  Version  : ' + $healthy.version)
    Write-Host ('  Instance : ' + $healthy.instance)
    Write-Host ('  Plans    : ' + $healthy.plans)
    Write-Host ''
    Write-Host 'Check the version above is the one you meant to publish, then open the app and'
    Write-Host 'confirm the Records list and the shared library are intact.'
    if ([string]::IsNullOrWhiteSpace([string]$healthy.instance)) {
        Write-Warning 'The instance label is blank, which means the service was started without -InstanceLabel. Two identical black console windows on that server are how the wrong one gets closed -- start it via "Start Quality Records Server.cmd" so it is labelled.'
    }
    exit 0
}

Write-Host ''
Write-Warning "The files are published, but $healthUrl has not answered within 60s."
Write-Host ''
Write-Host 'This is not necessarily a failed deployment -- it usually just means the service'
Write-Host 'has not been started yet. Check, in this order:'
Write-Host ''
Write-Host '  1. Has it been started at all? Run "Start Quality Records Server.cmd" on'
Write-Host '     NW-APPSERVER and read its console window -- it explains its own failures.'
Write-Host '  2. "Access is denied" on the listener means the URL reservation is missing.'
Write-Host '     Run "Configure Quality Records.ps1" on the server, elevated, once.'
Write-Host '  3. No reply at all, rather than a refusal? Suspect the firewall rule PROFILE.'
Write-Host '     The rule must be on the DOMAIN profile. If Get-NetConnectionProfile says the'
Write-Host '     active network is Private or Public, the rule silently never matches and'
Write-Host '     connections are DROPPED, not refused -- which looks exactly like a timeout'
Write-Host '     and sends you looking at the app instead of the firewall.'
Write-Host ''
Write-Host ('  4. Check it locally on the server first: Invoke-RestMethod ' + $localHealthUrl)
Write-Host '     If localhost works and nw-appserver does not, it is the network path, not the app.'
exit 1
