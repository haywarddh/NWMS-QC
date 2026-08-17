@echo off
setlocal
rem Day-to-day deployment of NWMS Quality Records to \\NW-APPSERVER\NWMS_QC.
rem Checks the service is stopped, publishes, then waits for you to start it on the
rem server and confirms /api/health. Nothing is ever executed remotely.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Deploy to NW-APPSERVER.ps1"
echo.
pause
endlocal
