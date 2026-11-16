$ErrorActionPreference = 'Stop'

$launcherPath = Join-Path $env:WINDIR 'Setup\Scripts\Start-DisableDefender.ps1'
if (!(Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
	throw "Disable-Defender prompt launcher was not staged: $launcherPath"
}

$runOncePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
$runOnceCommand = 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $launcherPath
New-Item -Path $runOncePath -Force | Out-Null
New-ItemProperty -Path $runOncePath -Name 'OptimizeOffline-DisableDefender' -PropertyType String -Value $runOnceCommand -Force | Out-Null
