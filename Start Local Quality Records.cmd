@echo off
setlocal
rem ===========================================================================
rem  Start Local Quality Records.cmd
rem  Runs the Quality Records service on Dave's laptop against the BUILT
rem  bundle -- localhost only, labelled LOCAL.
rem
rem  THIS IS NOT THE DAY-TO-DAY UI LOOP. For normal front-end work use the
rem  Vite dev server instead ("qc-dev.cmd", http://localhost:5173/), which
rem  hot-reloads and proxies /api to this same port. Use THIS launcher when
rem  you need to test what actually gets deployed: the compiled bundle in
rem  qc\dist\client, served by qc-api.ps1 exactly as NW-APPSERVER serves it.
rem  Run "npm run build" first -- a stale dist\ is a stale test.
rem
rem  -ListenAddress is 'localhost', so nothing here is reachable from the LAN
rem  and no URL reservation, elevation or firewall rule is involved. It also
rem  uses the LOCAL data folder (qc-api\data), never the server's records.
rem ===========================================================================

if /I "%COMPUTERNAME%"=="NW-APPSERVER" (
  echo This is the LOCAL test launcher and must not be used on NW-APPSERVER.
  echo Run "Start Quality Records Server.cmd" there instead.
  pause
  exit /b 1
)

set "ROOT=%~dp0"
set "PORT=8791"

if not exist "%ROOT%qc-api\qc-api.ps1" (
  echo Cannot find "%ROOT%qc-api\qc-api.ps1".
  pause
  exit /b 1
)
if not exist "%ROOT%qc\dist\client\index.html" (
  echo Cannot find "%ROOT%qc\dist\client\index.html".
  echo.
  echo The front end has not been built yet. In the qc folder run:
  echo     npm run build
  echo The deployable output is dist\client -- dist\server is a by-product.
  pause
  exit /b 1
)

echo.
echo Starting Quality Records (LOCAL) on http://localhost:%PORT%/
echo   Web root: %ROOT%qc\dist\client
echo   Data:     %ROOT%qc-api\data
echo.

start "NWMS Quality Records Service (LOCAL)" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%qc-api\qc-api.ps1" -ListenAddress "localhost" -Port %PORT% -WebRoot "%ROOT%qc\dist\client" -DataDir "%ROOT%qc-api\data" -InstanceLabel "LOCAL"

echo Waiting for the local service to come up...
powershell -NoProfile -Command "$ok = $null; for ($i = 0; $i -lt 20; $i++) { try { $r = Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/health' -TimeoutSec 2; if ($r.ok) { $ok = $r; break } } catch {}; Start-Sleep -Seconds 1 }; if ($ok) { Write-Host ''; Write-Host ('*** LOCAL SERVICE IS UP -- version ' + $ok.version + ' [' + $ok.instance + '], ' + $ok.plans + ' record(s) ***') -ForegroundColor Green; Start-Process 'http://localhost:%PORT%/' } else { Write-Host ''; Write-Host '*** LOCAL SERVICE DID NOT RESPOND -- read the service window for the reason ***' -ForegroundColor Red; Write-Host 'Most likely: another instance already holds qc-api\data\qc-api.lock, or the Vite dev server is already proxying to this port.' -ForegroundColor Yellow }"

echo.
pause
endlocal
