@echo off
setlocal
rem Publishes NWMS Quality Records to \\NW-APPSERVER\NWMS_QC without the
rem stop/start hand-holding -- use "Deploy to NW-APPSERVER.cmd" for the normal loop.
rem The publisher refuses to run if the service is still holding the data lock.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Publish Quality Records.ps1"
echo.
pause
endlocal
