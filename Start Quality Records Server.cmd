@echo off
setlocal
rem ===========================================================================
rem  Start Quality Records Server.cmd
rem  Starts the LIVE NWMS Quality Records service on NW-APPSERVER.
rem
rem  This launcher is PUBLISHED to \\NW-APPSERVER\NWMS_QC\ and is meant
rem  to be run THERE, from that folder, so %~dp0 resolves to the deployment root
rem  and web\ / data\ / qc-api.ps1 all sit beside it.
rem
rem  -ListenAddress "+" binds every interface, which is what the LAN needs and
rem  what requires the one-time URL reservation made by
rem  scripts\Configure Quality Records.ps1. Without it the service stops with a
rem  bare "Access is denied" from the listener and explains itself in its own
rem  window.
rem
rem  For a DEV instance, copy this launcher and change PORT to 8792, the label
rem  to DEV and -DataDir to its OWN data folder. A Dev instance sharing Live's
rem  data\ would let a test edit a controlled record -- and the service refuses
rem  to start twice against one data folder anyway.
rem ===========================================================================

if /I not "%COMPUTERNAME%"=="NW-APPSERVER" (
  echo This server launcher must only be run on NW-APPSERVER.
  echo.
  echo Users just browse to http://nw-appserver:8791/ -- no test PC should run
  echo its own service. On Dave's laptop use "Start Local Quality Records.cmd"
  echo instead, which listens on localhost only.
  echo.
  pause
  exit /b 1
)

set "ROOT=%~dp0"
set "PORT=8791"

rem  Both launchers are published to both shares, so guard against running the
rem  wrong one: starting the LIVE launcher from the Dev share would serve DEV
rem  data on Live's port 8791.
echo %ROOT% | find /I "_Dev" >nul
if not errorlevel 1 (
  echo REFUSING TO START.
  echo.
  echo This is the LIVE launcher ^(port 8791^) but it is sitting in a Dev share:
  echo   %ROOT%
  echo Starting it here would serve the DEV data on the LIVE port.
  echo.
  echo Use "Start Quality Records Dev Server.cmd" in this folder instead.
  echo.
  pause
  exit /b 1
)
if not exist "%ROOT%qc-api.ps1" (
  echo Cannot find "%ROOT%qc-api.ps1".
  echo.
  echo This launcher expects to be run from the PUBLISHED deployment folder
  echo ^(\\NW-APPSERVER\NWMS_QC\^), where qc-api.ps1 sits in the root.
  echo Publish first, from Dave's laptop: "Deploy to NW-APPSERVER.cmd".
  echo.
  pause
  exit /b 1
)
if not exist "%ROOT%web\index.html" (
  echo Cannot find "%ROOT%web\index.html".
  echo.
  echo The front end is missing, so the app would 404 on its own front page.
  echo Re-publish from Dave's laptop: "Deploy to NW-APPSERVER.cmd".
  echo.
  pause
  exit /b 1
)

echo.
echo ################################################################
echo ###                                                          ###
echo ###   !!!  THIS IS THE LIVE QUALITY RECORDS SERVER  !!!       ###
echo ###                                                          ###
echo ###   REAL QUALITY RECORDS AND REAL PHOTOGRAPHIC EVIDENCE     ###
echo ###   DO NOT CLOSE THIS WINDOW UNLESS YOU MEAN TO STOP IT     ###
echo ###                                                          ###
echo ################################################################
echo.
echo   URL       http://nw-appserver:%PORT%/
echo   Web root  %ROOT%web
echo   Data      %ROOT%data
echo.

start "NWMS Quality Records Service (LIVE)" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%qc-api.ps1" -ListenAddress "+" -Port %PORT% -WebRoot "%ROOT%web" -DataDir "%ROOT%data" -InstanceLabel "LIVE"

echo Waiting for the LIVE service to come up...
rem  The health check compares the PID in the reply against the one that was
rem  answering BEFORE we started. Without that, a stale instance still holding
rem  data\qc-api.lock answers happily, the new process exits with code 1, and the
rem  launcher cheerfully reports "SERVICE IS UP" -- a false pass in exactly the
rem  situation this check exists to catch.
powershell -NoProfile -Command "$before = $null; try { $before = (Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/health' -TimeoutSec 2).pid } catch {}; $ok = $null; for ($i = 0; $i -lt 20; $i++) { try { $r = Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/health' -TimeoutSec 2; if ($r.ok -and $r.pid -ne $before) { $ok = $r; break } } catch {}; Start-Sleep -Seconds 1 }; if ($ok) { Write-Host ''; Write-Host ('*** LIVE SERVICE IS UP -- http://nw-appserver:%PORT%/ -- version ' + $ok.version + ' [' + $ok.instance + '], pid ' + $ok.pid + ', ' + $ok.plans + ' record(s) ***') -ForegroundColor Green } elseif ($before) { Write-Host ''; Write-Host ('*** THE NEW SERVICE DID NOT START -- pid ' + $before + ' is STILL the one answering on port %PORT% ***') -ForegroundColor Red; Write-Host 'An older instance is still running and holding data\qc-api.lock. Stop it first:' -ForegroundColor Yellow; Write-Host '  Get-CimInstance Win32_Process -Filter \"Name=''powershell.exe''\" | Where-Object { $_.CommandLine -like ''*qc-api.ps1*'' }' -ForegroundColor Yellow; Write-Host '  (find it by command line, not by port -- http.sys reports the socket as PID 4)' -ForegroundColor Yellow } else { Write-Host ''; Write-Host '*** LIVE SERVICE DID NOT RESPOND -- read the service window, it explains its own failures ***' -ForegroundColor Red; Write-Host 'Most likely, in order:' -ForegroundColor Yellow; Write-Host '  1. Access is denied on the listener = no URL reservation. Run scripts\Configure Quality Records.ps1 elevated, once.' -ForegroundColor Yellow; Write-Host '  2. Another instance already holds data\qc-api.lock. Find it by command line, not by port -- http.sys reports PID 4.' -ForegroundColor Yellow }"

echo.
echo If it is up here but NOT reachable from another PC, suspect the firewall rule
echo PROFILE rather than the app: the rule must be on the DOMAIN profile, and if
echo Get-NetConnectionProfile says this machine's active network is Private or
echo Public the rule silently never matches. Connections are then DROPPED, not
echo refused, which looks exactly like a timeout.
echo.
pause
endlocal
