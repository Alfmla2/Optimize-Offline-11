<#
  .SYNOPSIS
    Cleans up after an interrupted Optimize-Offline run (window closed, crash or restart).

  .DESCRIPTION
    - Discards every Optimize-Offline image mount (install.wim, boot.wim, winre.wim), including mounts left in the
      NeedsRemount or Invalid state by a restart. DISM records mounts in the registry, so they survive a reboot.
    - Runs the DISM mount-point cleanup.
    - Unloads any offline registry hives the build left loaded (WIM_* / BOOT_*).
    - Deletes the OfflineTemp_* working folders next to this script.
    Nothing outside the OfflineTemp_* folders is deleted. Your source ISO and finished ISOs are not touched.

  .EXAMPLE
    .\Cleanup-Mounts.ps1          # asks before cleaning
    .\Cleanup-Mounts.ps1 -Force   # no prompt
#>
[CmdletBinding()]
Param ([Switch]$Force)

If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" $(If ($Force) {'-Force'})" -Verb RunAs
  return
}

$Root = $PSScriptRoot

# Never clean up underneath a running build: discarding its mounts would break it.
$Builds = @(Get-CimInstance Win32_Process -Filter "name='powershell.exe' or name='pwsh.exe'" | Where-Object { $PSItem.ProcessId -ne $PID -and $PSItem.CommandLine -match 'Start-Optimize|Optimize-Offline\.psm1' })
If ($Builds) { Write-Warning ('An Optimize-Offline build is still running (PID {0}). Let it finish or close its window, then run this again.' -f ($Builds.ProcessId -join ', ')); return }

$Mounts = @(Get-WindowsImage -Mounted | Where-Object { $PSItem.ImagePath -match '\\(install|boot|winre)\.wim$' })
$Temps = @(Get-ChildItem -LiteralPath $Root -Directory -Filter 'OfflineTemp_*' -ErrorAction SilentlyContinue)
$Hives = @(Get-ChildItem -Path Registry::HKEY_LOCAL_MACHINE -Name | Where-Object { $PSItem -like 'WIM_*' -or $PSItem -like 'BOOT_*' })

If (!$Mounts -and !$Temps -and !$Hives) { Write-Host 'Nothing to clean up: no image mounts, no loaded offline hives, no OfflineTemp folders.' -ForegroundColor Green; return }

Write-Host 'Found:' -ForegroundColor Cyan
$Mounts | ForEach-Object { Write-Host ('  Mount  [{0}]  {1}' -f $PSItem.MountStatus, $PSItem.MountPath) }
$Hives | ForEach-Object { Write-Host "  Hive   HKLM\$PSItem" }
$Temps | ForEach-Object { Write-Host "  Folder $($PSItem.FullName)" }
If (!$Force -and (Read-Host 'Discard these mounts and delete these folders? [Y/n]') -match '^[Nn]') { Write-Host 'Cancelled, nothing changed.'; return }

[GC]::Collect(); [GC]::WaitForPendingFinalizers()
ForEach ($Hive In $Hives) { $null = reg.exe unload "HKLM\$Hive" 2>&1; Write-Host "Unloaded hive HKLM\$Hive" }

ForEach ($Mount In $Mounts) {
  Try {
    # A restart leaves mounts as NeedsRemount; remounting first lets the discard succeed.
    If ($Mount.MountStatus -eq 'NeedsRemount') { $null = Mount-WindowsImage -Path $Mount.MountPath -Remount -ErrorAction Stop }
    $null = Dismount-WindowsImage -Path $Mount.MountPath -Discard -ErrorAction Stop
    Write-Host "Discarded $($Mount.MountPath)" -ForegroundColor Green
  }
  Catch { Write-Warning "Could not discard $($Mount.MountPath): $($PSItem.Exception.Message). The mount-point cleanup below usually releases it." }
}
$null = Clear-WindowsCorruptMountPoint
$null = dism.exe /English /Cleanup-Wim

ForEach ($Temp In $Temps) {
  Try { Remove-Item -LiteralPath $Temp.FullName -Recurse -Force -ErrorAction Stop }
  Catch {
    # Files copied out of the image keep TrustedInstaller ownership: take ownership, grant Administrators, retry.
    $null = takeown.exe /F $Temp.FullName /R /A /D Y 2>&1
    $null = icacls.exe $Temp.FullName /grant '*S-1-5-32-544:F' /T /C /Q 2>&1
    Remove-Item -LiteralPath $Temp.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
  If (Test-Path -LiteralPath $Temp.FullName) { Write-Warning "Could not fully delete $($Temp.FullName). Restart and run this again." } Else { Write-Host "Deleted $($Temp.FullName)" -ForegroundColor Green }
}
Write-Host ('Done. Image mounts still registered: {0}' -f @(Get-WindowsImage -Mounted).Count) -ForegroundColor Cyan
