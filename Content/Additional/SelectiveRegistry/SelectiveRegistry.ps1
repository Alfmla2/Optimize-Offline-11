RegHives -Load
# UCPD может блокировать изменение определенных разделов реестра, даже в офлайн-образе.
# Отключаем драйвер и политику, чтобы гарантировать применение всех настроек.
Log "Отключение UCPD (UserChoice Protection Driver)"
RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\UCPD" -Name "Start" -Value 4 -Type DWord
RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableUCPD" -Value 0 -Type DWord
Disable-ScheduledTask -TaskName "UCPD velocity" -TaskPath "\Microsoft\Windows\AppxDeploymentClient\"
Start-Sleep 1
If($SelectiveRegistry.DisableWindowsUpgrade) {

	$TargetReleaseVersionInfo = $null

	Switch ($Global:InstallInfo.Build) {
		"17134" { $TargetReleaseVersionInfo = "1803" }
		"17763" { $TargetReleaseVersionInfo = "1809" }
		"18362" { $TargetReleaseVersionInfo = "1903" }
		"18363" { $TargetReleaseVersionInfo = "1909" }
		"19041" { $TargetReleaseVersionInfo = "2004" }
		"19042" { $TargetReleaseVersionInfo = "2009" }
		"19043" { $TargetReleaseVersionInfo = "21H1" }
	}

	If ($Global:InstallInfo.Build -ge "19044") {
		$TargetReleaseVersionInfo = "21H2"
	}

	If ($Global:InstallInfo.Build -ge "22000") {
		$TargetReleaseVersionInfo = "22H2"
	}

	If ($Global:InstallInfo.Build -ge "22621") {
		$TargetReleaseVersionInfo = "23H2"
	}

	# Добавлено для Windows 11 24H2 (build 26100)
	If ($Global:InstallInfo.Build -ge "26100") {
		$TargetReleaseVersionInfo = "24H2"
	}
	
	If ($Global:InstallInfo.Build -ge "26200") {
		$TargetReleaseVersionInfo = "25H2"
	}
	
	If ($Global:InstallInfo.Build -ge "26300") {
		$TargetReleaseVersionInfo = "26H2"
	}

	If ($TargetReleaseVersionInfo){

		Log $OptimizeData.SelectiveRegistryWindowsUpgrade

		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value "2"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferUpdatePeriod" -Type DWord -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferUpgrade" -Type DWord -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferUpgradePeriod" -Type DWord -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetReleaseVersion" -Type DWord -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetReleaseVersionInfo" -Type String -Value $TargetReleaseVersionInfo

		If ($Global:InstallInfo.Build -ge "17134" -and $Global:InstallInfo.Build -le "20348") { RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ProductVersion" -Type String -Value "Windows 10" }

		If ($Global:InstallInfo.Build -ge "22000") { RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ProductVersion" -Type String -Value "Windows 11" }
		
	}
	Start-Sleep 1
}
If($SelectiveRegistry.DisableWindowsUpdateMicrosoft) {
	Log $OptimizeData.SelectiveRegistryWindowsUpdateMS
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DoNotConnectToWindowsUpdateInternetLocations" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DisableWindowsUpdateAccess" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Type String -Value " "
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Type String -Value " "
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "UpdateServiceUrlAlternate" -Type String -Value " "
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Type DWord -Value "1"
	Start-Sleep 1
}

If($SelectiveRegistry.DisableDriverUpdate) {
	Log $OptimizeData.SelectiveRegistryDriverUpdate
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value "0" 
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value "1"
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value "1"
	Start-Sleep 1
}

If($SelectiveRegistry.DormantOneDrive) {
	Log $OptimizeData.SelectiveRegistryDormantOneDrive
	RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -Type DWord -Value "0"
	Start-Sleep 1
}

# classic search in explorer
If($SelectiveRegistry.ClassicSearchExplorer -and $Global:InstallInfo.Build -ge '18363') {

	Log $OptimizeData.SelectiveRegistryClassicSearchExplorer

	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\CLSID\{1d64637d-31e9-4b06-9124-e83fb178ac6e}\TreatAs" -Name "(default)" -Value "{64bc32b5-4eec-4de7-972d-bd8bd0324537}" -Type String -Force

	Start-Sleep 1
}

If($SelectiveRegistry.RemoveTaskbarPinnedIcons){

	Log $OptimizeData.SelectiveRegistryRemoveTaskbarPinnedIcons

	## Disable taskbar taskview button
	RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type Dword -Value "0" -Force
	
	If($Global:InstallInfo.Build -ge '18362') {
		#Hide MeetNow icon in taskbar
		RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Type dword -Value "1"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Type dword -Value "1"
	}

	if($Global:InstallInfo.Build -le '19044'){
		RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\Windows\Explorer" -Name "NoPinningStoreToTaskbar" -Value 1 -Type DWord
		RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" -Name "MailPin" -Value 2 -Type DWord
		RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -Type DWord
	}

	If($Global:InstallInfo.Build -lt '22000') {
		# Disable News & Interests icon (Windows 10 only; Windows 11 replaced it with Widgets, and on Windows 11 hosts
		# the User Choice Protection Driver (UCPD) denies writes to these values, even in an offline hive)
		RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type dword -Value "2"
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type dword -Value "0"
	}

	If($Global:InstallInfo.Build -ge '22000') {
		#Remove Chat icon in taskbar
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -Type dword -Value "3"
		RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Type dword -Value "0"

		## Disable widgets button. UCPD denies writes to the per-user TaskbarDa value, so use the Widgets group policy,
		## which hides the taskbar button and turns Widgets off for all users.
		## UCPD matches on the end of the registry path ("...SOFTWARE\Policies\Microsoft\Dsh"), so it also blocks this value in the
		## offline hive while it is loaded as WIM_HKLM_SOFTWARE. Briefly load the image's SOFTWARE hive under a neutral name to write it.
		RegHives -Unload
		$null = reg.exe load "HKLM\WIM_OO_SW" (GetPath -Path $InstallMount -Child 'Windows\System32\Config\SOFTWARE')
		RegKey -Path "HKLM:\WIM_OO_SW\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Type DWord -Value 0
		[GC]::Collect(); [GC]::WaitForPendingFinalizers()
		$null = reg.exe unload "HKLM\WIM_OO_SW"
		RegHives -Load
	}

	Start-Sleep 1

}

If($SelectiveRegistry.W11ClassicContextMenu -and $Global:InstallInfo.Build -ge '22000') {
	Log $OptimizeData.SelectiveRegistryW11ClassicContextMenu
	# Classic context menus
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -Value "" -Type String -Force
	# The override is only reliably honored per-user (HKCU\Software\Classes), which maps to UsrClass.dat and cannot be pre-seeded offline, so apply it at each new user's first logon
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "W11ClassicContextMenu" -Value 'reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /f' -Type String
	Start-Sleep 1
}

if($SelectiveRegistry.DisableTeamsApp -and $Global:InstallInfo.Build -ge '10240') {
	Log $OptimizeData.SelectiveRegistryDisableTeamsApp
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -Value "0" -Type DWord -Force
	Start-Sleep 1
}

if($SelectiveRegistry.DisableVirtualizationSecurity -and $Global:InstallInfo.Build -ge '22000') {
	Log $OptimizeData.SelectiveRegistryDisableVirtualizationSecurity
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\DeviceGuard\Scenarios" -Name "HypervisorEnforcedCodeIntegrity" -Value "0" -Type DWord -Force
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value "0" -Type DWord -Force
	Start-Sleep 1
}

# Gaming and system responsiveness tweaks. Runs after the Xbox removal tweak, so Game Mode is re-enabled here even when Xbox apps were removed.
if($SelectiveRegistry.GamingResponsiveness -and $Global:InstallInfo.Build -ge '19041') {
	Log $OptimizeData.SelectiveRegistryGamingResponsiveness
	# Hardware-accelerated GPU scheduling (HAGS); ignored by GPUs/drivers that do not support it
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord
	# Short, variable, foreground-boosted quantums (0x26) for the focused game/app
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord
	# Stop Windows from power-throttling background processes (desktop-oriented; costs some battery on laptops)
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value 1 -Type DWord
	# Honor timer-resolution requests system-wide (Windows 11 22H2+ otherwise ignores them for minimized/occluded windows)
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord
	# MMCSS: reserve less CPU for background multimedia, disable network throttling, prioritize the Games task
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 10 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value -1 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Value 8 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Value 6 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Scheduling Category" -Value "High" -Type String
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "SFIO Priority" -Value "High" -Type String
	# Game DVR background recording off, Game Mode on
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord
	RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type DWord
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 -Type DWord
	# Xbox controller Guide button no longer pops up Game Bar mid-game
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord
	# Optimizations for windowed games (flip-model swap effect upgrade) and variable refresh rate for games without native VRR support
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\DirectX\UserGpuPreferences" -Name "DirectXUserGlobalSettings" -Value "VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;" -Type String
	# Fastest keyboard repeat delay/rate
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Type String
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Type String
	# No Filter Keys / Toggle Keys hotkey prompts
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -Type String
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Value "58" -Type String
	# Hung apps are treated as not responding sooner; services get 2 s to stop at shutdown instead of 5 s
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Desktop" -Name "HungAppTimeout" -Value "2000" -Type String
	RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
	# Delivery Optimization: download updates over HTTP only, no peer-to-peer uploading in the background
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Type DWord
	# Windows Update never restarts the PC automatically while someone is signed in
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
	# Recall/AI snapshot analysis off (no background screenshot indexing on Copilot+ PCs)
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0 -Type DWord
	# Edge does not keep processes running in the background or preload at sign-in
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0 -Type DWord
	RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord
	# Raw mouse input: disable Enhance Pointer Precision
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Type String
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String
	# No Sticky Keys prompt from repeated Shift presses mid-game
	RegKey -Path "HKLM:\WIM_HKCU\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "506" -Type String
	# Start startup apps immediately instead of after the built-in delay
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0 -Type DWord
	If ($Global:InstallInfo.Build -ge '26100') {
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1 -Type DWord
	}
	Start-Sleep 1
}



if ($SelectiveRegistry.ExplorerUIRibbon) {
	if ($Global:InstallInfo.Build -le "19044"){
		Log $OptimizeData.SelectiveRegistryExplorerUIRibbon
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Name "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}" -Value "" -Type String -Force
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Name "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}" -Value "" -Type String -Force
		Start-Sleep 1
	} elseif ($Global:InstallInfo.Build -eq "22000") {
		Log $OptimizeData.SelectiveRegistryExplorerUIRibbon
		# RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\CLSID\{d93ed569-3b3e-4bff-8355-3c44f6a52bb5}\InprocServer32" -Name "(default)" -Value "" -Type String -Force
		RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\CLSID\{d93ed569-3b3e-4bff-8355-3c44f6a52bb5}\InprocServer32" -Name "(default)" -Value "" -Type String -Force
		Start-Sleep 1
	}
}

RegHives -Unload

if($SelectiveRegistry.AmoledBlackTheme -and $Global:InstallInfo.Build -ge '10240') {
	Log $OptimizeData.SelectiveRegistryAmoledBlackTheme
	$AmoledReg = (Get-ChildItem -Path $OptimizeOffline.SelectiveRegistry -Filter AMOLED_black_theme.reg).FullName
	Import-Registry -Path $AmoledReg
	# Windows applies its default theme when a new account signs in for the first time, which overwrites the accent, title bar and
	# dark mode values imported into the default user profile above. Re-apply the per-user (HKEY_CURRENT_USER) part of the .reg at
	# each new account's first sign-in, after the default theme has been applied, then restart Explorer so the taskbar picks it up.
	$UserPart = [Collections.Generic.List[String]]@('Windows Registry Editor Version 5.00', '')
	$Keep = $false
	ForEach ($Line In (Get-Content -Path $AmoledReg)) {
		If ($Line -match '^\[') { $Keep = $Line -match 'HKEY_CURRENT_USER' }
		If ($Keep) { $UserPart.Add($Line) }
	}
	$UserPart | Set-Content -Path (GetPath -Path $InstallMount -Child 'Windows\Resources\Themes\AMOLED_black_theme_user.reg') -Encoding Unicode -Force
	RegHives -Load
	RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "AmoledBlackTheme" -Value 'cmd.exe /c reg.exe import "%WINDIR%\Resources\Themes\AMOLED_black_theme_user.reg" & taskkill.exe /f /im explorer.exe & start explorer.exe' -Type String
	RegHives -Unload
	Start-Sleep 1
}

if($SelectiveRegistry.RunAsTiContextMenu){
	Log $OptimizeData.SelectiveRegistryRunAsTiContextMenu
	Import-Registry -Path (Get-ChildItem -Path $OptimizeOffline.SelectiveRegistry -Filter RunAsTi.reg).FullName
	Start-Sleep 1
}

# Cloudflare DNS with DNS over HTTPS. DNS servers belong to network adapters, which only exist on the installed system, so this copies
# Set-CloudflareDNS.cmd into the image; the sample unattend.xml runs it at first sign-in if it is there.
if($SelectiveRegistry.CloudflareDNS){
	Log $OptimizeData.SelectiveRegistryCloudflareDNS
	$ScriptsFolder = GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts'
	$ScriptsFolder | Create
	Copy-Item -Path (GetPath -Path $OptimizeOffline.SelectiveRegistry -Child 'Set-CloudflareDNS.cmd') -Destination $ScriptsFolder -Force
	Start-Sleep 1
}

Clear-Host
