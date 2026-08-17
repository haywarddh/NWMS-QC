@echo off
setlocal
rem Backs up the live data\ folder (records, attachments, library, settings) from
rem \\NW-APPSERVER\NWMS_QC to its Backups\ folder, verifies the copy and
rem prunes backups older than 30 days (always keeping the most recent 3).
rem Safe to run while the service is running -- it only reads data\.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Backup Quality Records Data.ps1"
echo.
pause
endlocal
