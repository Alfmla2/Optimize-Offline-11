@ECHO OFF
CD /D "%~dp0"

REM ============================================================
REM REMOVE WINDOWS AI
REM ============================================================

IF EXIST "%WINDIR%\Setup\Scripts\RemoveWindowsAI.enabled" (
    PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Run-RemoveWindowsAI.ps1"

    DEL /F /Q ^
        "%WINDIR%\Setup\Scripts\RemoveWindowsAI.enabled" ^
        "%WINDIR%\Setup\Scripts\Run-RemoveWindowsAI.ps1" ^
        "%WINDIR%\Setup\Scripts\RemoveWindowsAI.ps1" ^
        "%WINDIR%\Setup\Scripts\RemoveWindowsAI-LICENSE.txt" >NUL 2>&1

    RMDIR /S /Q "%WINDIR%\Setup\Scripts\RemoveWindowsAIPackage" >NUL 2>&1
)


REM ============================================================
REM REMOVE ONEDRIVE
REM ============================================================

IF EXIST "%WINDIR%\Setup\Scripts\RemoveOneDrive.enabled" (
    PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Remove-OneDrive.ps1" -NoPrompt -SkipExplorerRestart

    DEL /F /Q "%WINDIR%\Setup\Scripts\RemoveOneDrive.enabled" >NUL 2>&1
)


REM ============================================================
REM DISABLE DEFENDER PROMPT
REM ============================================================

IF EXIST "%WINDIR%\Setup\Scripts\DisableDefender.enabled" (
    PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Register-DisableDefenderPrompt.ps1"

    DEL /F /Q "%WINDIR%\Setup\Scripts\DisableDefender.enabled" >NUL 2>&1
)


REM ============================================================
REM REFRESH EXPLORER
REM ============================================================

IF EXIST "%WINDIR%\Setup\Scripts\Refresh-Explorer.ps1" (
    PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Refresh-Explorer.ps1"
)

DEL /F /Q "%WINDIR%\Setup\Scripts\Refresh-Explorer.ps1" >NUL 2>&1
DEL /F /Q "%WINDIR%\Setup\Scripts\Register-DisableDefenderPrompt.ps1" >NUL 2>&1
DEL /F /Q "%WINDIR%\Setup\Scripts\Run_TI_SetupComplete_online.cmd" >NUL 2>&1


REM ============================================================
REM REMOVE ANSWER FILES
REM
REM Answer files should always be removed from the Windows\Panther
REM and Windows\System32\Sysprep directories immediately after
REM they have been processed.
REM ============================================================

DEL /F /Q "%WINDIR%\Panther\unattend.xml" >NUL 2>&1
DEL /F /Q "%WINDIR%\System32\Sysprep\unattend.xml" >NUL 2>&1


REM ============================================================
REM SELF DELETE
REM ============================================================

DEL /F /Q "%~f0" >NUL 2>&1
