@ECHO OFF
REM Cleans up image mounts and OfflineTemp folders left by an interrupted Optimize-Offline run.
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Cleanup-Mounts.ps1" %*
ECHO.
PAUSE
