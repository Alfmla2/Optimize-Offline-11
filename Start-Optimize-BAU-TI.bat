@ECHO OFF
REM Starts Start-Optimize-BAU-TI.ps1 with the execution policy bypassed for this run only (works from any account, including SYSTEM/TrustedInstaller).
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Optimize-BAU-TI.ps1" %*
