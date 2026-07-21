@echo off
REM start.bat - NirSoft Password Collector launcher (auto-elevates to Administrator)
REM
REM Portable: copy the project folder to any USB drive, any path on any PC.
REM A double-click shows one UAC prompt, then runs as Administrator.
REM
REM How auto-elevation works:
REM   1. `net session` detects whether we are already admin.
REM   2. If NOT admin, we use PowerShell's Start-Process -Verb RunAs to
REM      re-launch this very same batch file (%~f0) as Administrator, then
REM      `exit /b` the non-elevated instance so the user sees ONE console,
REM      not two.
REM   3. The re-launched instance passes the `net session` check and proceeds
REM      to invoke collector.ps1 normally.
REM
REM Edge cases handled:
REM   - Path with spaces: %~f0 contains the full quoted path; PowerShell uses
REM     single-quoted -Command so the path is passed through literally.
REM   - Infinite loop: avoided because the elevated instance succeeds the
REM     `net session` check on its first run.
REM   - No system installation: nothing added to registry, no scheduled task.

SETLOCAL

REM ----- Gihan IT Logo -----
echo.
echo  ===================================================
echo   ####   ##  ##   ##     ##     ##   ##     ##  ######
echo  ##      ##  ##   ##    ####    ###  ##     ##    ##
echo  ## ###  ##  #######   ##  ##   #######     ##    ##
echo  ##  ##  ##  ##   ##  ########  ##  ###     ##    ##
echo   ####   ##  ##   ##  ##    ##  ##   ##     ##    ##
echo  ===================================================
echo                      Gihan IT
echo       Copyright (C) 2025 - All Rights Reserved
echo  ===================================================
echo.

REM ----- Auto-elevate to Administrator if not already -----
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running with Administrator privileges - Good!
echo.

REM ----- Launch collector.ps1 -----
SET SCRIPTDIR=%~dp0

echo ================================================
echo Starting NirSoft Password Collector
echo ================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTDIR%collector.ps1"

echo.
echo ================================================
echo Script execution completed
echo ================================================
echo.
echo Press any key to close this window...
pause >nul

ENDLOCAL