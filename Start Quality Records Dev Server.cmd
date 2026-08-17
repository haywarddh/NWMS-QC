@echo off
setlocal
rem ===========================================================================
rem  Start Quality Records Dev Server.cmd
rem  Starts the DEV NWMS Quality Records service on NW-APPSERVER.
rem
rem  This launcher is PUBLISHED to \\NW-APPSERVER\NWMS_QC_Dev\ and is meant
rem  to be run THERE, from that folder, so %~dp0 resolves to the deployment root
rem  and web\ / data\ / qc-api.ps1 all sit beside it.
rem
rem  -ListenAddress "+" binds every interface, which is what the LAN needs and
rem  what requires the one-time URL reservation made by
rem  scripts\Configure Quality Records.ps1. Without it the service stops with a
rem  bare "Access is denied" from the listener and explains itself in its own
rem  window.
rem
rem  This is the DEV counterpart of "Start Quality Records Server.cmd". It runs on
rem  its OWN port and its OWN data\ folder inside the Dev share. A Dev instance
rem  sharing Live's data\ would let a test edit a controlled record -- and the
rem  service refuses to start twice against one data folder anyway.
rem ===========================================================================

if /I not "%COMPUTERNAME%"=="NW-APPSERVER" (
  echo This server launcher must only be run on NW-APPSERVER.
  echo.
  echo Users just browse to http://nw-appserver:8792/ -- no test PC should run
  echo its own service. On Dave's laptop use "Start Local Quality Records.cmd"
  echo instead, which listens on localhost only.
  echo.
  pause
  exit /b 1
)

set "ROOT=%~dp0"
set "PORT=8792"

rem  Both launchers are published to both shares, so guard against running the
rem  wrong one: starting the DEV launcher from the Live share would serve the
rem  controlled Live records on the Dev port.
echo %ROOT% | find /I "_Dev" >nul
if errorlevel 1 (
  echo REFUSING TO START.
  echo.
  echo This is the DEV launcher ^(port 8792^) but it is NOT in a Dev share:
  echo   %ROOT%
  echo Starting it here would expose the controlled LIVE records on the Dev port.
  echo.
  echo Use "Start Quality Records Server.cmd" in this folder instead.
  echo.
  pause
  exit /b 1
)
if not exist "%ROOT%qc-api.ps1" (
  echo Cannot find "%ROOT%qc-api.ps1".
  echo.
  echo This launcher expects to be run from the PUBLISHED deployment folder
  echo ^(\\NW-APPSERVER\NWMS_QC_Dev\^), where qc-api.ps1 sits in the root.
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
echo ----------------------------------------------------------------
echo    DEV Quality Records server  --  port %PORT%
echo.
echo    This is the UAT instance. Its records live in this share's own
echo    data\ folder and are NOT the controlled Live records.
echo    Live is a separate service on 8791, from the NWMS_QC share.
echo ----------------------------------------------------------------
echo.
echo   URL       http://nw-appserver:%PORT%/
echo   Web root  %ROOT%web
echo   Data      %ROOT%data
echo.

start "NWMS Quality Records Service (DEV)" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%qc-api.ps1" -ListenAddress "+" -Port %PORT% -WebRoot "%ROOT%web" -DataDir "%ROOT%data" -InstanceLabel "DEV"

echo Waiting for the DEV service to come up...
rem  The health check compares the PID in the reply against the one that was
rem  answering BEFORE we started. Without that, a stale instance still holding
rem  data\qc-api.lock answers happily, the new process exits with code 1, and the
rem  launcher cheerfully reports "SERVICE IS UP" -- a false pass in exactly the
rem  situation this check exists to catch.
powershell -NoProfile -Command "$before = $null; try { $before = (Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/health' -TimeoutSec 2).pid } catch {}; $ok = $null; for ($i = 0; $i -lt 20; $i++) { try { $r = Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/health' -TimeoutSec 2; if ($r.ok -and $r.pid -ne $before) { $ok = $r; break } } catch {}; Start-Sleep -Seconds 1 }; if ($ok) { Write-Host ''; Write-Host ('*** DEV SERVICE IS UP -- http://nw-appserver:%PORT%/ -- version ' + $ok.version + ' [' + $ok.instance + '], pid ' + $ok.pid + ', ' + $ok.plans + ' record(s) ***') -ForegroundColor Green } elseif ($before) { Write-Host ''; Write-Host ('*** THE NEW SERVICE DID NOT START -- pid ' + $before + ' is STILL the one answering on port %PORT% ***') -ForegroundColor Red; Write-Host 'An older instance is still running and holding data\qc-api.lock. Stop it first:' -ForegroundColor Yellow; Write-Host '  Get-CimInstance Win32_Process -Filter \"Name=''powershell.exe''\" | Where-Object { $_.CommandLine -like ''*qc-api.ps1*'' }' -ForegroundColor Yellow; Write-Host '  (find it by command line, not by port -- http.sys reports the socket as PID 4)' -ForegroundColor Yellow } else { Write-Host ''; Write-Host '*** DEV SERVICE DID NOT RESPOND -- read the service window, it explains its own failures ***' -ForegroundColor Red; Write-Host 'Most likely, in order:' -ForegroundColor Yellow; Write-Host '  1. Access is denied on the listener = no URL reservation. Run scripts\Configure Quality Records.ps1 elevated, once.' -ForegroundColor Yellow; Write-Host '  2. Another instance already holds data\qc-api.lock. Find it by command line, not by port -- http.sys reports PID 4.' -ForegroundColor Yellow }"

echo.
echo If it is up here but NOT reachable from another PC, suspect the firewall rule
echo PROFILE rather than the app: the rule must be on the DOMAIN profile, and if
echo Get-NetConnectionProfile says this machine's active network is Private or
echo Public the rule silently never matches. Connections are then DROPPED, not
echo refused, which looks exactly like a timeout.
echo.
pause
endlocal
