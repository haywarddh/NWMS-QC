<#
================================================================================
 Configure Quality Records.ps1 -- one-time administrator setup
================================================================================

 WHAT THIS DOES
 --------------
 Prepares NW-APPSERVER to run the NWMS Quality Records service (qc-api.ps1)
 on the LAN. Four jobs, in this order:

   1. Reserves http://+:<Port>/ for the account that will run the service, so
      it starts UNELEVATED forever after. Without the reservation,
      $listener.Start() fails with a bare "Access is denied".
   2. Creates the inbound firewall rule for <Port>, scoped to the DOMAIN
      profile -- and warns loudly if the machine's active network is not
      actually classified Domain, because then the rule silently never matches.
   3. Checks the things THIS app needs: web\index.html, a writable data\
      folder. Unlike the Planner it needs NO Sage ODBC driver, NO Access
      Database Engine and NO Node.js -- the front end is pre-built on Dave's
      laptop and served as plain files.
   4. Reports whether the privileged password is still the shipped default,
      and tells the operator to change it if so.

 WHERE IT MUST BE RUN
 --------------------
 ON NW-APPSERVER, signed in as an administrator, in an ELEVATED PowerShell
 window, from the published share:

     & '\\NW-APPSERVER\NWMS_QC\scripts\Configure Quality Records.ps1'

 Run it once per instance (Live on 8791, Dev on 8792 -- the reservation and
 the firewall rule are both per-port).

 WHAT IT REFUSES TO DO
 ---------------------
 * It refuses to run unelevated. netsh urlacl and New-NetFirewallRule both
   need Administrator, and half-completing this is worse than not starting.
 * It refuses to run on any machine other than -ExpectedComputer
   (default NW-APPSERVER). The guard exists so this is never fired at a test
   PC by mistake, leaving a stray wildcard reservation and an open port on a
   machine nobody is watching. Override it deliberately, by name, if you
   really do mean another box.
 * It NEVER touches the contents of data\. It will CREATE data\, data\plans\
   and data\attachments\ if they are missing (an empty folder destroys
   nothing), and it writes a single probe file which it deletes again to
   prove the runtime account can write there. It reads settings.json; it
   never writes it. Live records and photographic evidence are not this
   script's business.
 * It does nothing remotely and starts nothing. It configures Windows and
   then tells you which launcher to run yourself.

 Windows PowerShell 5.1. No ternary, no ??, no && chains.
================================================================================
#>

[CmdletBinding()]
param(
    # TCP port this instance listens on. 8791 = Live, 8792 = Dev.
    # Both the URL reservation and the firewall rule are per-port, so this is
    # the one value that decides which instance you are configuring.
    [int]$Port = 8791,

    # The account that will actually RUN qc-api.ps1 -- the URL reservation is
    # granted to it by name, and it is the account that needs write access to
    # data\. Defaults to whoever is running this script, which is right when
    # the administrator signing in is also the operator.
    [string]$RuntimeAccount = "$env:USERDOMAIN\$env:USERNAME",

    # Machine guard. Overridable so a deliberate second deployment is
    # possible, but never by accident.
    [string]$ExpectedComputer = 'NW-APPSERVER',

    # The deployed app folder. This script lives in scripts\, so the app root
    # is one level up -- the same idiom every other script in this package
    # uses, and it means the checks below look at the REAL deployed files
    # rather than whatever folder the window happened to be sitting in.
    [string]$AppRoot = ''
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# The SHA-256 of the shipped default privileged password ("nwms-quality").
# qc-api.ps1 seeds data\settings.json with this on a first run. Finding it
# still in place on a LIVE instance means every privileged action -- deleting
# a controlled record, overriding a sign-off -- is protected by a password
# that is written down in the README.
# ------------------------------------------------------------------------------
$DefaultPasswordHash = '8c438951def12cbb8b068e6a87dcdcffeede301546658ecd89501cc8618355bc'

$warnings = @()
function Add-Warning {
    param([string]$Message)
    $script:warnings += $Message
    Write-Warning $Message
}

# ------------------------------------------------------------------------------
# Guards -- both refusals, before anything is changed
# ------------------------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script as Administrator (right-click PowerShell, "Run as administrator") on NW-APPSERVER.'
}
if ($env:COMPUTERNAME -ne $ExpectedComputer) {
    throw "This package is configured for $ExpectedComputer, not $env:COMPUTERNAME. If you really mean this machine, re-run with -ExpectedComputer '$env:COMPUTERNAME'."
}

if (-not $AppRoot) {
    $AppRoot = Split-Path -Parent $PSScriptRoot
}
$AppRoot = [IO.Path]::GetFullPath($AppRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $AppRoot -PathType Container)) {
    throw "App folder not found: $AppRoot"
}

$testerHost = $ExpectedComputer.ToLowerInvariant()
$url = "http://+:$Port/"

Write-Host ''
Write-Host '=== NWMS Quality Records - one-time server configuration ===' -ForegroundColor Cyan
Write-Host "Machine:         $env:COMPUTERNAME"
Write-Host "App folder:      $AppRoot"
Write-Host "Port:            $Port"
Write-Host "Runtime account: $RuntimeAccount"
Write-Host ''

# ------------------------------------------------------------------------------
# 1. URL reservation
#
#    Two deliberate details here, both about netsh being a native exe:
#
#    * Its stderr is NOT redirected. In PS 5.1, "2>&1" on a native command
#      wraps each output line in an ErrorRecord (NativeCommandError) and trips
#      $ErrorActionPreference='Stop' even when the command succeeded.
#
#    * Its EXIT CODE is not usable as a "does it exist" test. Verified on this
#      estate: "netsh http show urlacl url=http://+:8791/" returns exit 0 with
#      an EMPTY listing when the reservation does not exist. Testing the exit
#      code alone therefore reports "already configured" for a URL that was
#      never reserved -- and the fault only shows up later as "Access is
#      denied" at listener start. So the presence test is the "Reserved URL"
#      line in the output, not the exit code.
# ------------------------------------------------------------------------------
function Get-UrlAclReservation {
    param([string]$ReservationUrl)

    $ErrorActionPreference = 'Continue'
    $output = @(& netsh.exe http show urlacl "url=$ReservationUrl")

    $exists = $false
    # A reservation can grant several accounts, so collect them all rather
    # than keeping whichever happened to be printed last.
    $users = @()
    foreach ($line in $output) {
        $text = [string]$line
        if ($text -match '(?i)Reserved\s+URL') { $exists = $true }
        if ($text -match '(?i)^\s*User:\s*(.+?)\s*$') { $users += $Matches[1] }
    }
    return New-Object psobject -Property @{ Exists = $exists; Users = @($users) }
}

Write-Host '--- URL reservation ---' -ForegroundColor Cyan
$reservation = Get-UrlAclReservation -ReservationUrl $url
if (-not $reservation.Exists) {
    $ErrorActionPreference = 'Continue'
    & netsh.exe http add urlacl "url=$url" "user=$RuntimeAccount" | Out-Null
    $addExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($addExit -ne 0) {
        throw "Unable to create the HTTP URL reservation for $url (netsh exit code $addExit). Confirm this window is elevated and that '$RuntimeAccount' is a valid account name."
    }
    Write-Host "Created URL reservation $url for $RuntimeAccount." -ForegroundColor Green
}
else {
    Write-Host "URL reservation already exists for $url"
    $grantedUsers = @($reservation.Users)
    if ($grantedUsers.Count -gt 0) {
        foreach ($grantedUser in $grantedUsers) { Write-Host "  Granted to: $grantedUser" }
        $matched = @($grantedUsers | Where-Object { $_ -ieq $RuntimeAccount })
        if ($matched.Count -eq 0) {
            # Not fatal: the existing grant may be a group the runtime account
            # belongs to. But a mismatch is the most common cause of "it still
            # says Access is denied after I configured it".
            Add-Warning "The existing reservation does not name '$RuntimeAccount' directly. If the service still fails to start with 'Access is denied', delete it and re-add it for the right account: netsh http delete urlacl url=$url"
        }
    }
}

# ------------------------------------------------------------------------------
# 2. Firewall rule (Domain profile) + the network-classification trap
# ------------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Firewall ---' -ForegroundColor Cyan
$firewallName = "NWMS Quality Records - TCP $Port"
$existingRule = Get-NetFirewallRule -DisplayName $firewallName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    New-NetFirewallRule -DisplayName $firewallName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Domain | Out-Null
    Write-Host "Created the Domain-profile firewall rule '$firewallName'." -ForegroundColor Green
}
else {
    Write-Host "The Domain-profile firewall rule '$firewallName' already exists."
}

# The trap, learned on the Planner and worth the noise every single time: a
# Domain-profile rule only matches while the active network is classified
# DomainAuthenticated. On a Private or Public classification the rule is
# simply never consulted and inbound packets are DROPPED rather than refused
# -- so the browser sits there and eventually times out, and every instinct
# says "the service is down" or "wrong port" rather than "wrong firewall
# profile". Check this before believing anything else.
$profiles = @()
try {
    $profiles = @(Get-NetConnectionProfile)
}
catch {
    Add-Warning "Could not read the network connection profiles ($($_.Exception.Message)). Check manually with Get-NetConnectionProfile that the active network is DomainAuthenticated."
}

if ($profiles.Count -gt 0) {
    $domainProfiles = @($profiles | Where-Object { $_.NetworkCategory -eq 'DomainAuthenticated' })
    foreach ($networkProfile in $profiles) {
        Write-Host "  Network '$($networkProfile.Name)' on '$($networkProfile.InterfaceAlias)' is classified: $($networkProfile.NetworkCategory)"
    }
    if ($domainProfiles.Count -eq 0) {
        Write-Host ''
        Write-Host '################################################################' -ForegroundColor Red
        Write-Host '###  WARNING: NO ACTIVE NETWORK IS CLASSIFIED AS DOMAIN      ###' -ForegroundColor Red
        Write-Host '################################################################' -ForegroundColor Red
        Write-Host ''
        Write-Host 'The firewall rule created above is scoped to the DOMAIN profile.' -ForegroundColor Yellow
        Write-Host 'While no active network is DomainAuthenticated, that rule is never' -ForegroundColor Yellow
        Write-Host 'consulted and inbound connections to this port are DROPPED, not' -ForegroundColor Yellow
        Write-Host 'refused. From another PC that looks EXACTLY like a timeout -- as if' -ForegroundColor Yellow
        Write-Host 'the service were down or the port wrong -- and you will spend the' -ForegroundColor Yellow
        Write-Host 'afternoon debugging the wrong thing.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Fix the network classification (the machine should authenticate to' -ForegroundColor Yellow
        Write-Host 'the domain controller), then re-run this script. Do not "solve" it' -ForegroundColor Yellow
        Write-Host 'by widening the rule to Private/Public: this app has no' -ForegroundColor Yellow
        Write-Host 'authentication at all, and the Domain scope is what keeps the' -ForegroundColor Yellow
        Write-Host 'quality records on the LAN.' -ForegroundColor Yellow
        Write-Host ''
        $warnings += 'No active network is classified DomainAuthenticated -- the Domain-profile firewall rule will silently never match.'
    }
    else {
        Write-Host 'Active network is Domain-classified, so the Domain-profile rule will match.' -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# 3. What this app actually needs
#    Deliberately short: no Sage ODBC driver, no System DSN, no Access
#    Database Engine, no Node.js. If you came here from the Planner's
#    configure script expecting those checks, their absence is correct.
# ------------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Application prerequisites ---' -ForegroundColor Cyan
Write-Host 'Windows PowerShell 5.1 only. No Sage ODBC, no Access engine, no Node.js needed here.'
Write-Host "  PowerShell version: $($PSVersionTable.PSVersion)"

$apiScript = Join-Path $AppRoot 'qc-api.ps1'
if (Test-Path -LiteralPath $apiScript) {
    Write-Host "  Service script found: $apiScript" -ForegroundColor Green
}
else {
    Add-Warning "The service script is missing: $apiScript. Publish the app to this folder before starting it."
}

# The built front end. A missing index.html produces a site that 404s on its
# own front page -- the single most embarrassing publish failure available.
$webRoot = Join-Path $AppRoot 'web'
$indexPath = Join-Path $webRoot 'index.html'
if (Test-Path -LiteralPath $indexPath) {
    $indexInfo = Get-Item -LiteralPath $indexPath
    Write-Host "  web\index.html found ($($indexInfo.Length) bytes, built $($indexInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Green
    $assetsPath = Join-Path $webRoot 'assets'
    if (Test-Path -LiteralPath $assetsPath -PathType Container) {
        $assetCount = @(Get-ChildItem -LiteralPath $assetsPath -Recurse -File).Count
        Write-Host "  web\assets holds $assetCount file(s)"
    }
    else {
        Add-Warning "web\assets\ is missing under $webRoot. index.html will load but its JavaScript and CSS will 404."
    }
    $fontsPath = Join-Path $webRoot 'fonts'
    if (-not (Test-Path -LiteralPath $fontsPath -PathType Container)) {
        Add-Warning "web\fonts\ is missing under $webRoot. The app self-hosts Barlow and JetBrains Mono; without these files every page -- including a printed ISIR a customer reads -- falls back to system fonts."
    }
}
else {
    Add-Warning "The built front end is missing: $indexPath. Without it the app answers 404 on its own front page. Run 'npm run build' on Dave's laptop and publish dist\client\ into web\."
}

# ------------------------------------------------------------------------------
#    data\ -- exists, and writable by the runtime account
# ------------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Data folder ---' -ForegroundColor Cyan
$dataDir = Join-Path $AppRoot 'data'
foreach ($folder in @($dataDir, (Join-Path $dataDir 'plans'), (Join-Path $dataDir 'attachments'))) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($folder)
        Write-Host "  Created empty folder: $folder" -ForegroundColor Green
    }
}
Write-Host "  Data folder: $dataDir"

$planCount = @(Get-ChildItem -LiteralPath (Join-Path $dataDir 'plans') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'index.json' }).Count
$attachmentCount = @(Get-ChildItem -LiteralPath (Join-Path $dataDir 'attachments') -File -ErrorAction SilentlyContinue).Count
Write-Host "  Holds $planCount record file(s) and $attachmentCount attachment(s)."
if ($planCount -gt 0 -or $attachmentCount -gt 0) {
    Write-Host '  This folder already holds live content. Nothing here is modified by this script.' -ForegroundColor Yellow
}

# Prove writability rather than infer it: create one probe file and delete it.
# This proves it for the account running THIS window, which is not necessarily
# the account that will run the service -- hence the ACL report below it.
$probePath = Join-Path $dataDir (".configure-write-test-" + $PID + ".tmp")
$probeWritten = $false
try {
    [IO.File]::WriteAllText($probePath, 'write test')
    $probeWritten = $true
    Write-Host "  Write test passed for the current account ($($identity.Name))." -ForegroundColor Green
}
catch {
    Add-Warning "Cannot write to $dataDir as $($identity.Name): $($_.Exception.Message). The service cannot save records or photographs without write access here."
}
finally {
    if ($probeWritten) { Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue }
}

# The runtime account may differ from the elevated administrator running this.
# PS 5.1 has no effective-permissions API, so report the ACEs and let the
# operator judge group membership rather than pretend to a verdict.
try {
    $acl = Get-Acl -Path $dataDir
    $direct = @()
    $writers = @()
    foreach ($ace in $acl.Access) {
        $rights = [string]$ace.FileSystemRights
        $isWrite = ($rights -match 'FullControl') -or ($rights -match 'Modify') -or ($rights -match 'Write')
        if ($ace.AccessControlType -eq 'Allow' -and $isWrite) {
            $writers += "$($ace.IdentityReference) [$rights]"
            if ([string]$ace.IdentityReference -ieq $RuntimeAccount) { $direct += $ace }
        }
    }
    if ($direct.Count -gt 0) {
        Write-Host "  ACL grants write access to '$RuntimeAccount' directly." -ForegroundColor Green
    }
    else {
        Write-Host "  No ACE names '$RuntimeAccount' directly. Write access may still come via one of these:" -ForegroundColor Yellow
        foreach ($writer in $writers) { Write-Host "    $writer" }
        Write-Host "  Confirm '$RuntimeAccount' is in one of the above, or grant it Modify on $dataDir." -ForegroundColor Yellow
    }
}
catch {
    Add-Warning "Could not read the ACL on $dataDir ($($_.Exception.Message)). Check manually that '$RuntimeAccount' has Modify."
}

# ------------------------------------------------------------------------------
# 4. Privileged password
# ------------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Privileged password ---' -ForegroundColor Cyan
$settingsPath = Join-Path $dataDir 'settings.json'
if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Host "  settings.json does not exist yet. The service seeds it on first start with the" -ForegroundColor Yellow
    Write-Host "  shipped default password 'nwms-quality' and warns about it at every start." -ForegroundColor Yellow
    $warnings += 'The privileged password will be seeded to the shipped default on first start -- change it.'
}
else {
    $hash = ''
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hash = [string]$settings.privilegedPasswordHash
    }
    catch {
        Add-Warning "settings.json could not be parsed ($($_.Exception.Message)). The service may refuse every privileged action. Do not delete it -- inspect it: $settingsPath"
    }
    if ($hash -ieq $DefaultPasswordHash) {
        Write-Host ''
        Write-Host '################################################################' -ForegroundColor Red
        Write-Host '###  THE PRIVILEGED PASSWORD IS STILL THE SHIPPED DEFAULT    ###' -ForegroundColor Red
        Write-Host '################################################################' -ForegroundColor Red
        Write-Host ''
        Write-Host "data\settings.json still holds the SHA-256 of 'nwms-quality', which is" -ForegroundColor Yellow
        Write-Host 'written down in qc-api\README.md. Every privileged action -- deleting a' -ForegroundColor Yellow
        Write-Host 'controlled record, overriding a sign-off -- is protected by a password' -ForegroundColor Yellow
        Write-Host 'anyone can look up. Change it before this instance carries real records.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'The recipe is in qc-api\README.md: hash the new password and write the' -ForegroundColor Yellow
        Write-Host "hex digest into privilegedPasswordHash in $settingsPath," -ForegroundColor Yellow
        Write-Host 'then restart the service.' -ForegroundColor Yellow
        Write-Host ''
        $warnings += 'The privileged password is still the shipped default -- change it before real records are entered.'
    }
    elseif ($hash) {
        Write-Host '  A non-default privileged password hash is set.' -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# Is a service already running against this data folder?
#    Informational. Nothing above requires the service to be stopped, but a
#    NEW url reservation only takes effect at the next listener start.
#    netstat and Get-NetTCPConnection are useless for finding it: http.sys
#    reports the listening socket as owned by PID 4 ("System").
# ------------------------------------------------------------------------------
$lockPath = Join-Path $dataDir 'qc-api.lock'
if (Test-Path -LiteralPath $lockPath) {
    $lockHeld = $true
    try {
        $probeStream = New-Object System.IO.FileStream -ArgumentList $lockPath, ([IO.FileMode]::Open), ([IO.FileAccess]::ReadWrite), ([IO.FileShare]::None)
        $probeStream.Dispose()
        $lockHeld = $false
    }
    catch { }
    if ($lockHeld) {
        Write-Host ''
        Write-Host '--- Running service ---' -ForegroundColor Cyan
        Write-Host '  A service is currently holding the lock on this data folder.' -ForegroundColor Yellow
        Write-Host '  Restart it so the URL reservation and firewall rule above apply to it:' -ForegroundColor Yellow
        Write-Host '    Get-CimInstance Win32_Process -Filter "Name=''powershell.exe''" |'
        Write-Host '      Where-Object { $_.CommandLine -like ''*qc-api.ps1*'' }'
        Write-Host '  (netstat / Get-NetTCPConnection will only show PID 4 "System" -- that is'
        Write-Host '   http.sys owning the socket, not the service.)'
    }
    else {
        Write-Host ''
        Write-Host "  A stale lock file was found at $lockPath (no process holds it). The service"
        Write-Host '  clears this itself on the next clean start.'
    }
}

# ------------------------------------------------------------------------------
# Summary and next step
# ------------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Configuration complete ===' -ForegroundColor Cyan
if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host "$($warnings.Count) thing(s) need your attention:" -ForegroundColor Yellow
    foreach ($warning in $warnings) { Write-Host "  - $warning" -ForegroundColor Yellow }
}
else {
    Write-Host 'No warnings. Windows is configured and the app files are in place.' -ForegroundColor Green
}
Write-Host ''
Write-Host "Next: run 'Start Quality Records Server.cmd' from $AppRoot on $ExpectedComputer."
Write-Host ''
Write-Host "Then confirm, on this machine:   Invoke-RestMethod http://localhost:$Port/api/health"
Write-Host "and from another PC:             Invoke-RestMethod http://$testerHost`:$Port/api/health"
Write-Host ''
Write-Host "Tester URL: http://$testerHost`:$Port/"
Write-Host ''
