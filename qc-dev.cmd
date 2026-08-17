@echo off
rem Dev-server launcher for the qc (NWMS Quality Records) app.
rem - Puts Node on PATH (harness sessions started before Node was installed
rem   don't have it).
rem - Clears the env vars that make @lovable.dev/vite-tanstack-config think
rem   it's running inside Lovable's cloud sandbox, which would force port
rem   8080 (in use by the Kelio system here).
rem - Pins the dev server to port 5173 explicitly.
set "PATH=C:\Program Files\nodejs;%PATH%"
set "DEV_SERVER__PROJECT_PATH="
set "LOVABLE_SANDBOX="
cd /d "C:\Users\dave\Documents\Claude\NWMS ISIR\qc"
npm run dev -- --port 5173 --strictPort
