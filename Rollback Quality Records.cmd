@echo off
setlocal
echo.
echo  NWMS QUALITY RECORDS - ROLLBACK
echo  ==============================
echo.
echo  This puts back the CODE from the most recent release snapshot.
echo.
echo    * data\ is NOT touched. Live quality records, the photographic evidence
echo      in data\attachments\ and data\settings.json are left exactly as they are.
echo    * A snapshot of the code that is live right now is taken first, so this
echo      rollback can itself be rolled back.
echo    * It refuses to run while the service still holds the data lock.
echo.
echo  For anything else, run it from a PowerShell window instead:
echo.
echo      scripts\Rollback Quality Records.ps1 -List
echo      scripts\Rollback Quality Records.ps1 -WhatIf
echo      scripts\Rollback Quality Records.ps1 -Release 20260817-142530
echo.
echo  Restoring old DATA needs -RestoreData and a typed confirmation. It destroys
echo  every record, sign-off and photograph created since that backup was taken.
echo.
echo  Close this window now to abort.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Rollback Quality Records.ps1"
echo.
pause
endlocal
