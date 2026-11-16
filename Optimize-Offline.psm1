Using module .\Src\Offline-Resources.psm1
#Requires -RunAsAdministrator
#Requires -Version 5.1
#Requires -Module Dism
<#
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2023 v5.8.218
	 Created on:   	11/20/2019 11:53 AM
	 Created by:   	BenTheGreat
	 Filename:     	Optimize-Offline.psm1
	 Version:       4.0.1.10-gdeliana-7.3-24H2
	 Last updated:	2026-10-31
	-------------------------------------------------------------------------
	 Module Name: Optimize-Offline

	 Fork notes:
	   - Removed DaRT 10 and Win32 Calculator integration (Win10-era only)
	   - Removed Windows 10-specific code paths
	   - SystemApps template uses PackageName as primary key (language-independent)
	   - Dedup integration locates packages dynamically per target language
	   - Edge integration locates CAB per build number (no hardcoded UBR)
	   - Removed strict image-language vs host-culture gating for integrations
	===========================================================================
#>
Function Optimize-Offline
{
	<#
	.EXTERNALHELP Optimize-Offline-help.xml
	#>

	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			HelpMessage = 'The full path to a Windows Installation Media ISO, or a Windows WIM, SWM or ESD file.')]
		[Object]$SourcePath,
		[Parameter(HelpMessage = 'Selectively or automatically deprovisions Windows Apps and removes their associated provisioning packages (.appx or .appxbundle).')]
		[ValidateSet('None', 'Select', 'Whitelist', 'Blacklist', 'All', IgnoreCase = $true)]
		[String]$WindowsApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of System Apps for selective removal.')]
		[ValidateSet('None', 'Select', 'Whitelist', 'Blacklist', 'All', IgnoreCase = $true)]
		[String]$SystemApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Capability Packages for selective removal.')]
		[ValidateSet('None', 'Select', 'Whitelist', 'Blacklist', 'All', IgnoreCase = $true)]
		[String]$Capabilities,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Cabinet File Packages for selective removal.')]
		[ValidateSet('None', 'Select', 'Whitelist', 'Blacklist', 'All', IgnoreCase = $true)]
		[String]$Packages,
		[ValidateSet('None', 'Select', 'List', 'All', IgnoreCase = $true)]
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Optional Features for selective disabling and enabling.')]
		[String]$FeaturesToEnable,
		[ValidateSet('None', 'Select', 'List', 'All', IgnoreCase = $true)]
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Optional Features for selective disabling and enabling.')]
		[String]$FeaturesToDisable,
		[Parameter(HelpMessage = 'Integrates the Developer Mode Feature into the image.')]
		[Switch]$DeveloperMode,
		[Parameter(HelpMessage = 'Integrates the Microsoft Windows Store and its required dependencies into the image.')]
		[Switch]$WindowsStore,
		[Parameter(HelpMessage = 'Integrates the Microsoft Edge Chromium Browser into the image.')]
		[Switch]$MicrosoftEdge,
		[Parameter(HelpMessage = 'Disable Windows defender while retaining the option to reactivate it.')]
		[Switch]$DormantDefender,
		[Parameter(HelpMessage = 'Integrates the Windows Server Data Deduplication Feature into the image.')]
		[Switch]$Dedup,
		[Parameter(HelpMessage = 'Applies optimized settings to the image registry hives.')]
		[Switch]$Registry,
		[Parameter(HelpMessage = 'Sets the output path')]
		[String]$OutputPath,
		[Parameter(HelpMessage = 'Integrates user-specific content added to the "Content/Additional" directory into the image when enabled within the hashtable.')]
		[Hashtable]$Additional = @{ Setup = $false; RemoveWindowsAI = $false; RemoveOneDrive = $false; DisableDefender = $false; Wallpaper = $false; SystemLogo = $false; LockScreen = $false; RegistryTemplates = $false; LayoutModification = $false; Unattend = $false; Drivers = $false; NetFx3 = $false },
		[Parameter(HelpMessage = 'Performs a clean-up of the Component Store by compressing all superseded components.')]
		[Switch]$ComponentCleanup,
		[Parameter(HelpMessage = 'Creates a new bootable Windows Installation Media ISO.')]
		[ValidateSet('Prompt', 'No-Prompt', IgnoreCase = $true)]
		[String]$ISO,
		[Parameter(Mandatory=$false)] [Switch]$populateLists,
		[Parameter(Mandatory=$false)] [Switch]$populateTemplates,
		[Parameter(Mandatory=$false)]
		[ValidateSet('Select', 'None', 'Fast', 'Maximum', 'Solid', IgnoreCase = $true)]
		[String]$CompressionType,
		[Parameter(Mandatory=$false)]
		[Hashtable]$SelectiveRegistry = @{
			DisableWindowsUpgrade = $false
			DisableWindowsUpdateMicrosoft = $false
			DisableDriverUpdate = $false
			DormantOneDrive = $false
			Disable3rdPartyApps = $false
			W11ClassicContextMenu = $false
			ExplorerUIRibbon = $false
			ClassicSearchExplorer = $false
			RemoveTaskbarPinnedIcons = $false
			DisableTeamsApp = $false
			DisableVirtualizationSecurity = $false
			RunAsTiContextMenu = $false
			AmoledBlackTheme = $false
		},
		[Parameter(HelpMessage = 'Shutdown PC on script completion')]
		[Switch]$ShutDownOnComplete = $false,
		[Parameter(HelpMessage = 'Removal of windows services.')]
		[ValidateSet('None', 'List', 'Advanced', 'Select', IgnoreCase = $true)]
		[String]$Services,
		[Parameter(HelpMessage = 'Set USB booting support')]
		[ValidateSet('Off', 'Legacy', 'UEFI', IgnoreCase = $true)]
		[String]$FlashToUSB = "Off",
		[Parameter(Mandatory = $false, HelpMessage = 'Set USB Drive to flash the ISO')]
		[Int]$FlashUSBDriveNumber = -1
	)

	Begin
	{
		#region Pre-Processing Block
		$LocalScope | Add-Member -MemberType NoteProperty -Name Variables -Value (Get-Variable).Name -PassThru | Add-Member -MemberType NoteProperty -Name ErrorActionPreference -Value $ErrorActionPreference -PassThru | Add-Member -MemberType NoteProperty -Name ProgressPreference -Value $ProgressPreference
		$ErrorActionPreference = 'SilentlyContinue'
		$Global:ProgressPreference = 'SilentlyContinue'
		$Host.UI.RawUI.BackgroundColor = 'Black'
		If ($PSVersionTable.PSVersion.Major -eq 7) { $PSStyle.OutputRendering = 'Host' }
		Clear-Host
		Test-Requirement
		If (Get-WindowsImage -Mounted) { Dismount-Image; Clear-Host }
		[Void](Clear-WindowsCorruptMountPoint)
		((GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log'), (GetPath -Path $Env:SystemRoot -Child 'Logs\CBS\CBS.log')) | Purge -ErrorAction Ignore
		$Global:Error.Clear()
		#endregion Pre-Processing Block
	}
	Process
	{
		#region Create the Working File Structure
		Set-Location -Path $OptimizeOffline.Directory
		[Environment]::CurrentDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
		@(Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory), (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log') | Purge -ErrorAction Ignore
		Try
		{
			@($TempDirectory, $ImageFolder, $WorkFolder, $ScratchFolder, $LogFolder) | Create -ErrorAction Stop
		}
		Catch
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToCreateWorkingFileStructure)
			Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory | Purge -ErrorAction Ignore
			Break
		}
		#endregion Create the Working File Structure

		#region Media Export
		$SourcePath = [IO.FileInfo]$SourcePath
		$allowedExtensions = @('.iso', '.wim', '.swm', '.esd')
		If (-not $SourcePath.Exists -or [String]$SourcePath.Extension.ToLower() -notin $allowedExtensions) {
			Add-Type -AssemblyName System.Windows.Forms
			$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
				InitialDirectory = [Environment]::GetFolderPath('Desktop')
				Filter = 'All allowed types|*.wim;*.swm;*.iso;*.esd;*.WIM;*.SWM;*.ISO;*.ESD'
				Multiselect = $false
				AddExtension = $true
				CheckPathExists = $true
			}
			$null = $FileBrowser.ShowDialog()
			if($FileBrowser.FileName){
				$SourcePath = Get-Item -Path $FileBrowser.FileName
			}
		}

		if(-not $SourcePath.Exists) { Throw ('Invalid source path: "{0}"' -f [String]$SourcePath) }

		Switch ($SourcePath.Extension)
		{
			'.ISO'
			{
				Try{
					$DrivesBefore = [System.Collections.ArrayList]@()
					Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Free -eq 0} | ForEach-Object -Process {
						[Void]$DrivesBefore.Add($PSItem.Name)
					}
					[Void](Mount-DiskImage -ImagePath $SourcePath.FullName -StorageType ISO)
					$ISOMount = "$((Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Free -eq 0 -and $_.Name -notin $DrivesBefore}).Name):"
				} Catch {
					$ISOMount = ""
				}

				If (!(Get-ChildItem -Path (GetPath -Path $ISOMount -Child sources) -Filter install* -File))
				{
					$PSCmdlet.WriteWarning($OptimizeData.InvalidWindowsInstallMedia -f $SourcePath.Name)
					Do { [Void](Dismount-DiskImage -ImagePath $SourcePath.FullName) }
					While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)
					$TempDirectory | Purge
					Break
				}
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.ExportingMedia -f $SourcePath.Name)
				Write-Host ($OptimizeData.ExportingMedia -f $SourcePath.Name) -ForegroundColor Cyan
				$ISOMedia = Create -Path (GetPath -Path $TempDirectory -Child $SourcePath.BaseName) -PassThru
				$ISOMedia | Export-DataFile -File ISOMedia
				ForEach ($Item In Get-ChildItem -Path $ISOMount -Recurse)
				{
					$ISOExport = $ISOMedia.FullName + $Item.FullName.Replace($ISOMount, $null)
					$destPathDir = $(Split-Path $ISOExport)
					If (!(Test-Path -Path $destPathDir)) {
						[Void](New-Item -path $(Split-Path $ISOExport) -ItemType Directory -Force)
					}
					Copy-Item -Path $Item.FullName -Destination $ISOExport
				}
				Do { [Void](Dismount-DiskImage -ImagePath $SourcePath.FullName) }
				While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)

				If ((Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Measure-Object).Count -gt 1 -and (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Select-Object -First 1).Extension -eq '.SWM')
				{
					Try
					{
						$InstallWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Select-Object -First 1 | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName
						$SwmFiles = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName
					}
					Catch [Management.Automation.ItemNotFoundException] { Break }
				}
				Else
				{
					Try { $InstallWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install.* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
					Catch [Management.Automation.ItemNotFoundException] { Break }
				}

				# Extract boot.wim only when additional boot-level drivers are present.
				If ($Additional.Drivers -and (Get-ChildItem -Path $OptimizeOffline.BootDrivers -Include *.inf -Recurse -Force))
				{
					Try { $BootWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter boot.* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
					Catch [Management.Automation.ItemNotFoundException] { Break }
				}
				Break
			}
			Default
			{
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName)
				Write-Host ($OptimizeData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName) -ForegroundColor Cyan
				Try { $InstallWim = Get-ChildItem -Path $SourcePath.FullName -Filter $SourcePath.Name | Copy-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Rename-Item -NewName ('install' + $SourcePath.Extension) -PassThru | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
				Catch [Management.Automation.ItemNotFoundException] { Break }
				If ($SourcePath.Extension -eq '.SWM')
				{
					Try { $SwmFiles = Get-ChildItem -Path $SourcePath.DirectoryName -Filter "$($SourcePath.BaseName)*$($SourcePath.Extension)" -Exclude $SourcePath.Name -Recurse | Where-Object -Property Name -Like "$($SourcePath.BaseName)*.swm" | Copy-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru }
					Catch [Management.Automation.ItemNotFoundException] { Break }
					$I = 2
					$SwmFiles = Get-ChildItem -Path $ImageFolder -Include $SwmFiles.PSChildName -File -Recurse | ForEach-Object -Process { Rename-Item -Path $PSItem -NewName ('install{0:D1}.swm' -f $I++) -PassThru }
				}
				If ($ISO) { Remove-Variable -Name ISO }
				Break
			}
		}

		If ([IO.File]::Exists($InstallWim))
		{
			Switch ([IO.Path]::GetExtension($InstallWim))
			{
				'.ESD' { $DynamicParams.ESD = $true; Break }
				'.SWM' { $DynamicParams.SWM = $true; Break }
				Default { $DynamicParams.WIM = $true; Break }
			}
			If ($BootWim)
			{
				If ([IO.File]::Exists($BootWim)) { $DynamicParams.BootImage = $true }
			}
		}
		Else
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToReturnInstallImage -f $ImageFolder)
			$TempDirectory | Purge
			Break
		}
		#endregion Media Export

		#region USB device selection
		$null = $USBDrive
		If ($FlashToUSB.ToLower().Trim() -ne "off" -and !$populateLists -and !$populateTemplates) {
			$USBDrive = Get-Disk | Where-Object BusType -eq USB
			If($FlashUSBDriveNumber -ge 0) {
				$USBDrive = $USBDrive | Where-Object Number -eq $FlashUSBDriveNumber
			} Else {
				$USBDrive = $USBDrive | Out-GridView -Title 'Select USB Drive to Format' -OutputMode Single
			}
		}
		#endregion USB device selection

		#region Image and Metadata Validation
		$Host.UI.RawUI.WindowTitle = 'Reading Windows edition metadata.'
		Write-Host 'Reading Windows edition metadata from the installation image...' -ForegroundColor Cyan
		$WindowsImages = Get-WindowsImage -ImagePath $InstallWim -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1
		If ($WindowsImages.Count -gt 1)
		{
			$Host.UI.RawUI.WindowTitle = $OptimizeData.SelectWindowsEdition
			Write-Host $OptimizeData.SelectWindowsEdition -ForegroundColor Cyan
			$WindowsImages | Select-Object -Property @{ Label = 'Index'; Expression = { ($PSItem.ImageIndex) } }, @{ Label = 'Name'; Expression = { ($PSItem.ImageName) } }, @{ Label = 'Size (GB)'; Expression = { '{0:N2}' -f ($PSItem.ImageSize / 1GB) } } | Format-Table -AutoSize | Out-Host
			$ValidIndexes = @($WindowsImages | ForEach-Object -Process { [int]$PSItem.ImageIndex })
			Do
			{
				$EditionIndex = Read-Host 'Enter the Index of the Windows edition to optimize'
				$ImageIndex = $null
				If ($EditionIndex -match '^\d+$')
				{
					$CandidateIndex = [int]$EditionIndex
					If ($CandidateIndex -in $ValidIndexes) { $ImageIndex = $CandidateIndex }
				}
				If ($null -eq $ImageIndex) { Write-Warning 'Enter one of the Index values shown above.' }
			}
			While ($null -eq $ImageIndex)
		}
		Else { $ImageIndex = 1 }

		Try
		{
			$Host.UI.RawUI.WindowTitle = "Validating Image Metadata."
			$InstallInfo = $InstallWim | Get-ImageData -Index $ImageIndex -ErrorAction Stop
			$Global:InstallInfo = $InstallInfo
			$InstallInfo | ConvertTo-Json | Out-File -FilePath "$($OptimizeOffline.GUI.Main)\image_info.json" -Encoding UTF8 -Force -ErrorAction Ignore
		}
		Catch
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
			$TempDirectory | Purge
			Break
		}

		If($OutputPath.ToLower().Trim() -eq 'select'){
			Add-Type -AssemblyName System.Windows.Forms
			If($SourcePath.Extension.ToLower() -eq '.iso'){
				$SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
				$SaveFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
				$SaveFileDialog.FileName = ($($InstallInfo.Edition).Replace(' ', '') + "_$($InstallInfo.Build)")
				$SaveFileDialog.Filter = "ISO files (*.iso)| *.iso"
				If($SaveFileDialog.ShowDialog() -eq 'Ok'){
					$OutputPath = $SaveFileDialog.FileName
				}
			} Else {
				$FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
				$null = $FolderBrowserDialog.ShowDialog()
				$OutputPath = $FolderBrowserDialog.SelectedPath
			}
		}

		# For 24H2+ always ensure boot.wim is mounted so HW bypass tweaks can be applied.
		If ($InstallInfo.Build -ge 22000 -and -not $BootWim -and $ISOMedia.Exists)
		{
			Try { $BootWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter boot.* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
			Catch [Management.Automation.ItemNotFoundException] { Break }
			$DynamicParams.BootImage = $true
		}

		If ($InstallInfo.VersionTable.Major -ne 10)
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageVersion -f $InstallInfo.Version)
			$TempDirectory | Purge
			Break
		}
		If ($InstallInfo.Architecture -ne 'amd64')
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageArch -f $InstallInfo.Architecture)
			$TempDirectory | Purge
			Break
		}
		If ($InstallInfo.InstallationType.Contains('WindowsPE'))
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageType -f $InstallInfo.InstallationType)
			$TempDirectory | Purge
			Break
		}
		If ($InstallInfo.Build -lt '17134')
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageBuild -f $InstallInfo.Build)
			$TempDirectory | Purge
			Break
		}

		# LTSC has no Store / WindowsApps by default.
		If ($InstallInfo.Name -like "*LTSC*")
		{
			$DynamicParams.LTSC = $true
			If ($WindowsApps -notin @('None')) { Remove-Variable -Name WindowsApps }
			# Fork (24H2): do NOT forcibly disable -WindowsStore on LTSC.
			# IoT Enterprise LTSC 24H2 users often add Store explicitly; respecting the
			# user's -WindowsStore switch is the correct behavior. The WindowsStore
			# integration has its own guards (file existence, already-in-image check).
		}

		# Verify that the Edge CAB actually exists for the target build; otherwise disable integration.
		If ($MicrosoftEdge.IsPresent)
		{
			$EdgeCabPattern = If ($InstallInfo.Build -ge '18362') {
				"Microsoft-Windows-Chromium-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).*.cab"
			} Else {
				"Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"
			}
			If (-not (Get-ChildItem -Path $OptimizeOffline.MicrosoftEdge -Filter $EdgeCabPattern -File -ErrorAction Ignore)) {
				Log ("Edge package for build {0} not found in {1}. Disabling Edge integration." -f $InstallInfo.Build, $OptimizeOffline.MicrosoftEdge) -Type Warning
				$MicrosoftEdge = ![Switch]::Present
			}
		}
		#endregion Image and Metadata Validation

		#region Image Preparation
		If (!$DynamicParams.WIM)
		{
			$ExportToWimParams = @{
				SourceImagePath      = $InstallWim
				SourceIndex          = $ImageIndex
				DestinationImagePath = '{0}\install.wim' -f $WorkFolder
				CheckIntegrity       = $true
				ScratchDirectory     = $ScratchFolder
				LogPath              = $DISMLog
				LogLevel             = 1
				ErrorAction          = 'Stop'
			}
			If ($DynamicParams.ESD) { $ExportToWimParams.CompressionType = 'Maximum' }
			Else { $ExportToWimParams.SplitImageFilePattern = ('{0}\install*.swm' -f $ImageFolder) }
			Try
			{
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				Write-Host ($OptimizeData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf)) -ForegroundColor Cyan
				[Void](Export-WindowsImage @ExportToWimParams)
				$ImageIndex = 1
			}
			Catch
			{
				$PSCmdlet.WriteWarning($OptimizeData.FailedExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				$TempDirectory | Purge
				Break
			}
			Finally
			{
				$InstallWim | Purge
				If ($DynamicParams.SWM) { $SwmFiles | Purge }
			}
			Try
			{
				$InstallWim = Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $ImageFolder -Force -PassThru | Select-Object -ExpandProperty FullName
				$InstallInfo = $InstallWim | Get-ImageData -Index $ImageIndex -ErrorAction Stop
			}
			Catch
			{
				$PSCmdlet.WriteWarning($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
				$TempDirectory | Purge
				Break
			}
		}

		If ($Global:Error.Count -ne 0) { $Global:Error.Clear() }

		Try
		{
			Log ($OptimizeData.SupportedImageBuild -f $InstallInfo.Build)
			Start-Sleep 3
			$OptimizeTimer = [Diagnostics.Stopwatch]::StartNew()
			$InstallMount | Create -ErrorAction Stop
			$MountInstallParams = @{
				ImagePath        = $InstallWim
				Index            = $ImageIndex
				Path             = $InstallMount
				CheckIntegrity   = $true
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				LogLevel         = 1
				ErrorAction      = 'Stop'
			}
			Log ($OptimizeData.MountingImage -f $InstallInfo.Name)
			[Void](Mount-WindowsImage @MountInstallParams)
			RegHives -Load
			Get-ItemProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion" | Export-DataFile -File CurrentVersion
			# Fork (24H2): resolve the active ControlSet once; reused by all downstream tweaks.
			$CCS = if (Get-Command -Name Get-OfflineCurrentControlSet -ErrorAction SilentlyContinue) { Get-OfflineCurrentControlSet } else { 'ControlSet001' }
			RegHives -Unload
		}
		Catch
		{
			Log ($OptimizeData.FailedMountingImage -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
			Stop-Optimize
		}

		# Extract winre.wim only when recovery drivers need to be injected.
		If ($Additional.Drivers -and (Get-ChildItem -Path $OptimizeOffline.RecoveryDrivers -Include *.inf -Recurse -Force))
		{
			$WinREPath = GetPath -Path $InstallMount -Child 'Windows\System32\Recovery\winre.wim'
			If (Test-Path -Path $WinREPath)
			{
				$RecoveryWim = Move-Item -Path $WinREPath -Destination $ImageFolder -Force -PassThru | Select-Object -ExpandProperty FullName
				$DynamicParams.RecoveryImage = $true
			}
		}

		If ($DynamicParams.BootImage)
		{
			$BootWimImageIndex = 0
			$BootWimImages = Get-WindowsImage -ImagePath $BootWim -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1
			Foreach($Image in $BootWimImages) {
				If ($Image.ImageDescription -like "Microsoft Windows Setup*") {
					$BootWimImageIndex = $Image.ImageIndex
				}
			}
			Try
			{
				$BootInfo = $BootWim | Get-ImageData -Index $BootWimImageIndex -ErrorAction Stop
			}
			Catch
			{
				Log ($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $BootWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				$BootMount | Create -ErrorAction Stop
				$MountBootParams = @{
					Path             = $BootMount
					ImagePath        = $BootWim
					Index            = $BootWimImageIndex
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.MountingImage -f $BootInfo.Name)
				[Void](Mount-WindowsImage @MountBootParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedMountingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
		}

		If ($DynamicParams.RecoveryImage)
		{
			Try { $RecoveryInfo = $RecoveryWim | Get-ImageData -Index 1 -ErrorAction Stop }
			Catch { Log ($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $RecoveryWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]; Stop-Optimize }
			Try
			{
				$RecoveryMount | Create -ErrorAction Stop
				$MountRecoveryParams = @{
					Path             = $RecoveryMount
					ImagePath        = $RecoveryWim
					Index            = 1
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.MountingImage -f $RecoveryInfo.Name)
				[Void](Mount-WindowsImage @MountRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedMountingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
		}

		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).ImageHealthState -eq 'Healthy')
		{
			Log $OptimizeData.PreOptimizedImageHealthHealthy
			Start-Sleep 3; Clear-Host
		}
		Else
		{
			Log $OptimizeData.PreOptimizedImageHealthCorrupted -Type Error
			Stop-Optimize
		}
		#endregion Image Preparation

		#region Populate Templates / Lists
		If ($populateLists -or $populateTemplates) {
			# Fork (24H2): pre-flight check for Out-GridView availability.
			# Without it, $ErrorActionPreference = 'SilentlyContinue' swallows the
			# exception thrown by Out-GridView when Microsoft.PowerShell.GraphicalHost
			# is missing, $Selection stays $null, and the *List.json files are never
			# written — the user sees no error and no dialog.
			If ($populateLists) {
				$GridViewState = Test-InteractiveGridView -Detailed
				If (-not $GridViewState.Available) {
					$WarnMsg = ('-populateLists is unavailable because {0} ' +
						'Templates will still be written, but *List.json files will NOT be created. ' +
						'To create them, install the "Windows PowerShell ISE" optional feature ' +
						'(DISM /Online /Add-Package /PackagePath:<ISE-FoD.cab>) and restart PowerShell, ' +
						'then re-run with -populateLists. Alternatively, edit the corresponding ' +
						'*List.json manually based on the generated templates.') -f $GridViewState.Reason
					$PSCmdlet.WriteWarning($WarnMsg)
					Log $WarnMsg -Type Warning

					# Downgrade to template-only mode.
					$populateTemplates = $true
					$populateLists     = $false
				}
			}
			Try {
				# --- WindowsApps ---
				$Items = [System.Collections.ArrayList]@( )
				$ItemsGUI = [System.Collections.ArrayList]@( )
				Get-AppxPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog | ForEach-Object -Process {
					[Void]$Items.Add([String]$PSItem.DisplayName)
					[Void]$ItemsGUI.Add(@{
						PackageName = [String]$PSItem.PackageName
						DisplayName = [String]$PSItem.DisplayName
						Selected = $false
					})
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.WindowsAppsTemplate)"
				[ordered]@{ DisplayName = $Items } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.WindowsAppsTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				$ItemsGUI | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.WindowsApps -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $WindowsApps -in @('Whitelist', 'Blacklist')) {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.WindowsAppsList)"
					Log "DEBUG: WindowsApps items = $($Items.Count)"
					Start-Sleep 1
					$Selection = $Items | Out-GridView -Title "Select windows apps to save to the $($WindowsApps)" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ DisplayName = $Selection } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.WindowsAppsList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}

				# --- SystemApps (language-independent: PackageName + DisplayName) ---
				# Fork (24H2): Get-SystemPackages reads the offline SOFTWARE hive
				# (HKLM:\WIM_HKLM_SOFTWARE\...\InboxApplications) and therefore requires
				# the hives to be loaded. Previously the call ran with hives unloaded,
				# producing an empty template and an empty GridView.
				RegHives -Load
				$SystemAppsData = [System.Collections.ArrayList]@( )
				$ItemsGUI = [System.Collections.ArrayList]@( )
				Get-SystemPackages | ForEach-Object -Process {
					If ($_.PackageName) {
						# Fork: use PSCustomObject instead of [ordered]@{} so that Out-GridView
						# displays proper columns (PackageName / DisplayName) and serializes
						# correctly to JSON instead of emitting Key/Value dictionary entries.
						[Void]$SystemAppsData.Add([PSCustomObject]@{
							PackageName = [String]$_.PackageName
							DisplayName = [String]$_.DisplayName
						})
						[Void]$ItemsGUI.Add(@{
							PackageName = [String]$_.PackageName
							DisplayName = [String]$_.DisplayName
							Selected = $false
						})
					}
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.SystemAppsTemplate)"
				[ordered]@{
					SystemApps = @($SystemAppsData)
				} | ConvertTo-Json -Depth 3 | Out-File -FilePath $OptimizeOffline.Lists.SystemAppsTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				$ItemsGUI | ConvertTo-Json -Depth 3 | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.SystemApps -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $SystemApps -in @('Whitelist', 'Blacklist')) {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.SystemAppsList)"
					Start-Sleep 1
					$Selection = $SystemAppsData | Out-GridView -Title "Select system apps to save to the $($SystemApps)" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ SystemApps = @($Selection) } | ConvertTo-Json -Depth 3 | Out-File -FilePath $OptimizeOffline.Lists.SystemAppsList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}
				# Fork (24H2): Get-SystemPackages больше не размонтирует hive (это фикс для
				# System App Removal). Но DISM-операции ниже (Capabilities, Packages, Features)
				# не работают, пока SOFTWARE hive смонтирован через RegLoadKey — получают
				# "file is being used by another process". Размонтируем здесь; Services
				# ниже сам сделает RegHives -Load.
				RegHives -Unload

				# --- Capabilities ---
				$Items = [System.Collections.ArrayList]@( )
				$ItemsGUI = [System.Collections.ArrayList]@( )
				Get-CapabilityPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog | ForEach-Object -Process {
					[Void]$Items.Add([String]$PSItem.Name)
					[Void]$ItemsGUI.Add(@{ Name = [String]$PSItem.Name; Selected = $false })
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.CapabilitiesTemplate)"
				[ordered]@{ Name = $Items } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.CapabilitiesTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				$ItemsGUI | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.Capabilities -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $Capabilities -in @('Whitelist', 'Blacklist')) {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.CapabilitiesList)"
					Start-Sleep 1
					$Selection = $Items | Out-GridView -Title "Select capabilities to save to the $($Capabilities)" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ Name = $Selection } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.CapabilitiesList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}

				# --- Packages ---
				$Items = [System.Collections.ArrayList]@( )
				$ItemsGUI = [System.Collections.ArrayList]@( )
				Get-OtherWindowsPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog | ForEach-Object -Process {
					[Void]$Items.Add([String]$PSItem.PackageName)
					[Void]$ItemsGUI.Add(@{ PackageName = [String]$PSItem.PackageName; Selected = $false })
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.PackagesTemplate)"
				[ordered]@{ PackageName = $Items } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.PackagesTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				$ItemsGUI | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.Packages -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $Packages -in @('Whitelist', 'Blacklist')) {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.PackagesList)"
					Start-Sleep 1
					$Selection = $Items | Out-GridView -Title "Select packages to save to the $($Packages)" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ PackageName = $Selection } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.PackagesList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}

				# --- Features (enabled -> FeaturesToDisable, disabled -> FeaturesToEnable) ---
				$Items = [System.Collections.ArrayList]@( )
				$ItemsGUI = [System.Collections.ArrayList]@( )
				Get-OptionalEnabledFeatures -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog | ForEach-Object -Process {
					[Void]$Items.Add([String]$PSItem.FeatureName)
					[Void]$ItemsGUI.Add(@{
						FeatureName = [String]$PSItem.FeatureName
						States = @("Enabled", "Disabled")
						State = "Enabled"
						OriginalState = "Enabled"
					})
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.FeaturesToDisableTemplate)"
				[ordered]@{ FeatureName = $Items } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.FeaturesToDisableTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $FeaturesToDisable -eq 'List') {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.FeaturesToDisableList)"
					Start-Sleep 1
					$Selection = $Items | Out-GridView -Title "Select features to disable for saving to the FeaturesToDisable list" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ FeatureName = $Selection } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.FeaturesToDisableList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}

				$Items = [System.Collections.ArrayList]@( )
				Get-OptionalDisabledFeatures -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog | ForEach-Object -Process {
					[Void]$Items.Add([String]$PSItem.FeatureName)
					[Void]$ItemsGUI.Add(@{
						FeatureName = [String]$PSItem.FeatureName
						States = @("Enabled", "Disabled")
						State = "Disabled"
						OriginalState = "Disabled"
					})
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.FeaturesToEnableTemplate)"
				[ordered]@{ FeatureName = $Items } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.FeaturesToEnableTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				Start-Sleep 1
				If ($populateLists -and $FeaturesToEnable -eq 'List') {
					Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.FeaturesToEnableList)"
					Start-Sleep 1
					$Selection = $Items | Out-GridView -Title "Select features to enable for saving to the FeaturesToEnable list" -PassThru
					If ($Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						[ordered]@{ FeatureName = $Selection } | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.FeaturesToEnableList -Encoding UTF8 -Force -ErrorAction Ignore
					}
				}
				$ItemsGUI | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.Features -Encoding UTF8 -Force -ErrorAction Ignore

				# --- Services ---
				RegHives -Load
				$Items = Get-ImageServices
				Log "DEBUG: Found $($Items.Count) services."
				$ItemsGUI = [System.Collections.ArrayList]@( )
				$Items | ForEach-Object -Process {
					[Void]$ItemsGUI.Add(@{
						Name = [String]$PSItem.name
						Description = $PSItem.description
						OriginalStart = $PSItem.startLabel
						Start = $PSItem.startLabel
						Starts = $OptimizeOffline.ServicesStartLabels
					})
				}
				$JsonInfo = $OptimizeOffline.ServicesStartLabels | ForEach-Object -Process {
					"$($OptimizeOffline.ServicesStartLabels.IndexOf($_)) = $_"
				}
				Log "$($OptimizeData.Populating) $($OptimizeOffline.Lists.ServicesTemplate)"
				[ordered]@{
					__Info = $JsonInfo
					Services = $Items
				} | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.Lists.ServicesTemplate -Encoding UTF8 -Force -ErrorAction Ignore
				$ItemsGUI | ConvertTo-Json | Out-File -FilePath $OptimizeOffline.GUI.RemovalTemplates.Services -Encoding UTF8 -Force -ErrorAction Ignore
				If ($populateLists -and $Services -in @('List', 'Advanced')) {
					# Вычисляем путь к файлу один раз, чтобы не путать парсер вложенными кавычками
					$ListFilePath = $OptimizeOffline.Lists."Services$Services"

					Log "$($OptimizeData.Populating) $ListFilePath"
					Start-Sleep 1

					$Selection = $Items | Out-GridView -Title "Select services to save to the list" -PassThru

					If ($null -ne $Selection) {
						If ($Selection -isnot [array]) { $Selection = @($Selection) }
						Log "DEBUG: Selection count: $($Selection.Count)"

						If ($Services -eq 'List') {
							$JsonData = [ordered]@{
								__Info = $JsonInfo
								Services = [System.Collections.ArrayList]@()
							}
							foreach ($Item in $Selection) { [Void]$JsonData.Services.Add($Item.name) }
						}
						Else {
							$JsonData = [ordered]@{
								__Info = $JsonInfo
								Services = @($Selection)
							}
						}

						Try {
							$JsonData | ConvertTo-Json -Depth 3 -ErrorAction Stop | Out-File -FilePath $ListFilePath -Encoding UTF8 -Force -ErrorAction Stop
							Log "DEBUG: Successfully wrote to $ListFilePath"
						}
						Catch {
							Log "DEBUG: Failed to write JSON: $($_.Exception.Message)" -Type Error
						}
					}
					Else {
						Log "DEBUG: Selection was null or cancelled, skipping write."
					}
				}
				RegHives -Unload

			} Catch {
				# Fork: $Error[0] может быть $null, если ошибка уже поглощена внутри Get-* функций.
				# Write-Log имеет [Mandatory] [string]$Text — на $null выдаёт
				# ParameterArgumentValidationErrorEmptyStringNotAllowed, что маскирует реальную причину.
				If ($Error.Count -gt 0 -and $null -ne $Error[0]) {
					Log ([String]$Error[0])
				} Else {
					Log "populateLists failed with no ErrorRecord (see DISM.log)" -Type Warning
				}
			} Finally {
				Dismount-Image
				@($TempDirectory, $DISMLog, $(GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log')) | Purge -ErrorAction Ignore
			}
			Return
		}
		#endregion Populate Templates / Lists
		$InteractiveGridView = $null
		If ($PSBoundParameters.WindowsApps -eq 'Select' -or
			$PSBoundParameters.SystemApps   -eq 'Select' -or
			$PSBoundParameters.Capabilities -eq 'Select' -or
			$PSBoundParameters.Packages     -eq 'Select' -or
			$PSBoundParameters.FeaturesToDisable -eq 'Select' -or
			$PSBoundParameters.FeaturesToEnable  -eq 'Select' -or
			$PSBoundParameters.Services     -eq 'Select') {
			$InteractiveGridView = Test-InteractiveGridView -Detailed
		}
		#region Provisioned App Package Removal
		$RemovedPackages = $RemovedPackages = @{};
		$AppxPackages = Get-AppxPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog
		If ($WindowsApps -in $AllowedRemovalOptions)
		{
			Try
			{
				$Host.UI.RawUI.WindowTitle = "Remove WindowsApps Packages."
				$appsToRemove = [System.Collections.ArrayList]@()

				Switch ($PSBoundParameters.WindowsApps)
				{
					'Select'
					{
						If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
							$PSCmdlet.WriteWarning(("WindowsApps Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
							Break
						}
						$appsToRemove = $AppxPackages | Out-GridView -Title "Select the Provisioned App Packages to Remove." -PassThru
						Break
					}
					'Whitelist'
					{
						If (Test-Path -Path $OptimizeOffline.Lists.WindowsAppsList)
						{
							$AppsJson = Get-Content -Path $OptimizeOffline.Lists.WindowsAppsList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty DisplayName
							$AppxPackages | ForEach-Object -Process {
								$ToRemove = $true
								Foreach($App in $AppsJson){
									If ($PSItem.DisplayName -eq $App -or ($App -Match "\*" -and $PSItem.DisplayName -like $App)) { $ToRemove = $false; Break }
								}
								If($ToRemove){ [void]$appsToRemove.Add($PSItem) }
							}
						}
						Break
					}
					'Blacklist'
					{
						If (Test-Path -Path $OptimizeOffline.Lists.WindowsAppsList)
						{
							$AppsJson = Get-Content -Path $OptimizeOffline.Lists.WindowsAppsList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty DisplayName
							$AppxPackages | ForEach-Object -Process {
								Foreach($App in $AppsJson){
									If ($PSItem.DisplayName -eq $App -or ($App -Match "\*" -and $PSItem.DisplayName -like $App)) { [void]$appsToRemove.Add($PSItem); Break }
								}
							}
						}
						Break
					}
					'All' { $appsToRemove = $AppxPackages; Break }
				}

				$appsToRemove | ForEach-Object -Process {
					$RemoveAppxParams = @{
						Path             = $InstallMount
						PackageName      = $PSItem.PackageName
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.RemovingWindowsApp -f $PSItem.DisplayName)
					Try { [Void](Remove-AppxProvisionedPackage @RemoveAppxParams) }
					Catch { Log ("Skipped Appx package (cannot be removed): {0}" -f $PSItem.DisplayName) -Type Error -ErrorRecord $Error[0] }
					$RemovedPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
				}
				$DynamicParams.WindowsApps = $($appsToRemove.Count -gt 0)
			}
			Catch
			{
				Log $OptimizeData.FailedRemovingWindowsApps -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		$AppxPackages = Get-AppxPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog
		#endregion Provisioned App Package Removal

		#region System App Removal (language-independent)
		If ($SystemApps -in $AllowedRemovalOptions)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove System Apps."
			Start-Sleep 5

			RegHives -Load
			$InboxAppsKey = "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications"
			$InboxAppsPackages = Get-SystemPackages

			If ($InboxAppsPackages)
			{
				$RemovedSystemApps = @{}
				$packagesToRemove = [System.Collections.ArrayList]@()

				Try {
					Switch ($PSBoundParameters.SystemApps)
					{
						'Select'
						{
							If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
								$PSCmdlet.WriteWarning(("SystemApps Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
								Break
							}
							$PSCmdlet.WriteWarning($OptimizeData.SystemAppsWarning)
							$packagesToRemove = $InboxAppsPackages | Out-GridView -Title "Remove System Apps." -PassThru
							Break
						}
						'Whitelist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.SystemAppsList)
							{
								$Raw = Get-Content -Path $OptimizeOffline.Lists.SystemAppsList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
								$ListItems = $null; $MatchByPkg = $false
								If ($Raw.SystemApps) { $ListItems = @($Raw.SystemApps); $MatchByPkg = $true }
								ElseIf ($Raw.DisplayName) { $ListItems = @($Raw.DisplayName | ForEach-Object { @{ DisplayName = $_ } }); $MatchByPkg = $false }

								If ($ListItems) {
									$InboxAppsPackages | ForEach-Object -Process {
										$Pkg = $_
										$IsListed = $false
										Foreach ($ListedApp in $ListItems) {
											If ($MatchByPkg -and $ListedApp.PackageName -and $Pkg.PackageName) {
												If ($Pkg.PackageName -eq $ListedApp.PackageName -or ($ListedApp.PackageName -match '\*' -and $Pkg.PackageName -like $ListedApp.PackageName)) { $IsListed = $true; Break }
											} ElseIf (-not $MatchByPkg -and $ListedApp.DisplayName -and $Pkg.DisplayName) {
												If ($Pkg.DisplayName -eq $ListedApp.DisplayName -or ($ListedApp.DisplayName -match '\*' -and $Pkg.DisplayName -like $ListedApp.DisplayName)) { $IsListed = $true; Break }
											}
										}
										If (-not $IsListed) { [void]$packagesToRemove.Add($Pkg) }
									}
								}
							}
							Break
						}
						'Blacklist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.SystemAppsList)
							{
								$Raw = Get-Content -Path $OptimizeOffline.Lists.SystemAppsList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
								$ListItems = $null; $MatchByPkg = $false
								If ($Raw.SystemApps) { $ListItems = @($Raw.SystemApps); $MatchByPkg = $true }
								ElseIf ($Raw.DisplayName) { $ListItems = @($Raw.DisplayName | ForEach-Object { @{ DisplayName = $_ } }); $MatchByPkg = $false }

								If ($ListItems) {
									$InboxAppsPackages | ForEach-Object -Process {
										$Pkg = $_
										$IsListed = $false
										Foreach ($ListedApp in $ListItems) {
											If ($MatchByPkg -and $ListedApp.PackageName -and $Pkg.PackageName) {
												If ($Pkg.PackageName -eq $ListedApp.PackageName -or ($ListedApp.PackageName -match '\*' -and $Pkg.PackageName -like $ListedApp.PackageName)) { $IsListed = $true; Break }
											} ElseIf (-not $MatchByPkg -and $ListedApp.DisplayName -and $Pkg.DisplayName) {
												If ($Pkg.DisplayName -eq $ListedApp.DisplayName -or ($ListedApp.DisplayName -match '\*' -and $Pkg.DisplayName -like $ListedApp.DisplayName)) { $IsListed = $true; Break }
											}
										}
										If ($IsListed) { [void]$packagesToRemove.Add($Pkg) }
									}
								}
							}
							Break
						}
						'All' { $packagesToRemove = $InboxAppsPackages }
					}

					$packagesToRemove | ForEach-Object -Process {
						$PackageKey = (GetPath -Path $InboxAppsKey -Child $PSItem.PackageName) -replace 'HKLM:', 'HKLM'

						# --- DEBUG START ---
						Log "DEBUG: PackageKey = $PackageKey"
						Log "DEBUG: Key exists = $(Test-Path -LiteralPath ('HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications\' + $PSItem.PackageName))"
						Log "DEBUG: WIM_HKLM_SOFTWARE exists = $(Test-Path -LiteralPath 'HKLM:\WIM_HKLM_SOFTWARE')"
						# --- DEBUG END ---

						Log ($OptimizeData.RemovingSystemApp -f $PSItem.DisplayName)
						Try {
							$retCode = StartExe $REG -Arguments ('DELETE "{0}" /F' -f $PackageKey) -ErrorAction Stop
							# --- DEBUG START ---
							Log "DEBUG: reg delete returned $retCode"
							# --- DEBUG END ---
						} Catch {
							Log "DEBUG: StartExe threw: $($_.Exception.Message)" -Type Error -ErrorRecord $_
							$retCode = 1
						}
						If ($retCode -eq 1) { Log ($OptimizeData.FailedRemovingSystemApp -f $PSItem.DisplayName) -Type Error; Continue }
						$RemovedSystemApps.Add($PSItem.DisplayName, $PSItem.PackageName)
						$RemovedPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
						Start-Sleep 1
					}
					Log "DEBUG: Exited System App Removal ForEach loop"

					$DynamicParams.SystemApps = $($packagesToRemove.Count -gt 0)
				} Catch {
					Log $OptimizeData.FailedRemovingSystemApps -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
			}
			Log "DEBUG: About to RegHives -Unload in System App Removal"
			RegHives -Unload
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			Log "DEBUG: System App Removal region done"
		}
		#endregion System App Removal

		$DynamicParams.RemovedPackages = $RemovedPackages;

		#region Removed Package Clean-up
		If ($DynamicParams.WindowsApps)
		{
			# 24H2+: purge WindowsApps folder only when every provisioned app has been removed.
			If ($AppxPackages.Count -eq 0) { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Purge -Force }
		}
		RegHives -Load
		$Visibility = [Text.StringBuilder]::New('hide:')
		If ($RemovedPackages.'Microsoft.WindowsMaps' -or ($AppxPackages | Where-Object {$_.DisplayName -eq "Microsoft.WindowsMaps"}).Count -eq 0)
		{
			Log "Applying Windows Maps removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\Maps" -Name "AutoUpdateEnabled" -Value 0 -Type DWord
			If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\MapsBroker") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\MapsBroker" -Name "Start" -Value 4 -Type DWord }
			[Void]$Visibility.Append('maps;maps-downloadmaps;')
		}
		If (($RemovedPackages.'Microsoft.Wallet' -or ($AppxPackages | Where-Object {$_.DisplayName -eq "Microsoft.Wallet"}).Count -eq 0) -and (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\WalletService")) {
			Log "Applying Microsoft Wallet removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\WalletService" -Name "Start" -Value 4 -Type DWord
		}
		If (($RemovedPackages.'Microsoft.XboxIdentityProvider' -and ($RemovedPackages.Keys -like "*Xbox*").Count -gt 1 -or $RemovedPackages.'Microsoft.XboxGameCallableUI') -or ($AppxPackages | Where-Object {$_.DisplayName -like "*Xbox*"}).Count -eq 0)
		{
			Log "Applying Xbox apps removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AudioCaptureEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "CursorCaptureEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "ShowStartupPanel" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord
			@("xbgm", "XblAuthManager", "XblGameSave", "xboxgip", "XboxGipSvc", "XboxNetApiSvc") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
			[Void]$Visibility.Append('gaming-gamebar;gaming-gamedvr;gaming-broadcasting;gaming-gamemode;gaming-xboxnetworking;quietmomentsgame;')
		}
		If ($RemovedPackages.'Microsoft.YourPhone' -or $RemovedPackages.'Microsoft.Windows.CallingShellApp' -or $($AppxPackages | Where-Object {$_.DisplayName -eq "Microsoft.YourPhone"}).Count -eq 0)
		{
			Log "Applying YourPhone removal tweak"
			Start-Sleep 1
			[Void]$Visibility.Append('mobile-devices;mobile-devices-addphone;mobile-devices-addphone-direct;')
			If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\PhoneSvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\PhoneSvc" -Name "Start" -Value 4 -Type DWord }
		}
		If ($RemovedPackages.'Microsoft.BioEnrollment')
		{
			Log "Applying Microsoft BioEnrollment removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics" -Name "Enabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider" -Name "Enabled" -Value 0 -Type DWord
			If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\WbioSrvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\WbioSrvc" -Name "Start" -Value 4 -Type DWord }
			[Void]$Visibility.Append('signinoptions-launchfaceenrollment;signinoptions-launchfingerprintenrollment;')
			$DynamicParams.BioEnrollment = $true
		}
		If ($RemovedPackages.'Microsoft.Windows.SecureAssessmentBrowser')
		{
			Log "Applying SecureAssessmentBrowser removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowScreenMonitoring" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowTextSuggestions" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "RequirePrinting" -Value 0 -Type DWord
		}
		If ($RemovedPackages.'Microsoft.Windows.ContentDeliveryManager' -or $SelectiveRegistry.Disable3rdPartyApps)
		{
			Log "Applying ContentDeliveryManager removal tweak"
			Start-Sleep 1
			@("ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "RotatingLockScreenEnabled",
				"RotatingLockScreenOverlayEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContentEnabled",
				"SubscribedContent-202913Enabled", "SubscribedContent-202914Enabled", "SubscribedContent-280797Enabled", "SubscribedContent-280811Enabled", "SubscribedContent-280812Enabled",
				"SubscribedContent-280813Enabled", "SubscribedContent-280814Enabled", "SubscribedContent-280815Enabled", "SubscribedContent-280810Enabled", "SubscribedContent-280817Enabled",
				"SubscribedContent-310091Enabled", "SubscribedContent-310092Enabled", "SubscribedContent-310093Enabled", "SubscribedContent-310094Enabled", "SubscribedContent-314558Enabled",
				"SubscribedContent-314559Enabled", "SubscribedContent-314562Enabled", "SubscribedContent-314563Enabled", "SubscribedContent-314566Enabled", "SubscribedContent-314567Enabled",
				"SubscribedContent-338380Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338381Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338382Enabled",
				"SubscribedContent-338389Enabled", "SubscribedContent-338386Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-346480Enabled", "SubscribedContent-346481Enabled",
				"SubscribedContent-353694Enabled", "SubscribedContent-353695Enabled", "SubscribedContent-353696Enabled", "SubscribedContent-353697Enabled", "SubscribedContent-353698Enabled",
				"SubscribedContent-353699Enabled", "SubscribedContent-88000044Enabled", "SubscribedContent-88000045Enabled", "SubscribedContent-88000105Enabled", "SubscribedContent-88000106Enabled",
				"SubscribedContent-88000161Enabled", "SubscribedContent-88000162Enabled", "SubscribedContent-88000163Enabled", "SubscribedContent-88000164Enabled", "SubscribedContent-88000165Enabled",
				"SubscribedContent-88000166Enabled") | ForEach-Object -Process { RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $PSItem -Value 0 -Type DWord }
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "NoCloudApplicationNotification" -Value 1 -Type DWord

			If ($InstallInfo.Build -ge "22000") {
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -Type String -Value '{"pinnedList": [{}]}'
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins_ProviderSet" -Type Dword -Value "0"
			}
		}
		If ($DormantDefender.IsPresent -or $RemovedPackages.'Microsoft.Windows.SecHealthUI' -or $RemovedPackages.'Microsoft.SecHealthUI' -or (($AppxPackages | Where-Object {$_.DisplayName -eq 'Microsoft.SecHealthUI'}).Count -eq 0 -and $InstallInfo.Build -ge 22000))
		{
			Log "Applying Defender removal tweak"
			Start-Sleep 1
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender" -Name "PUAProtection" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine" -Name "MpEnablePus" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Reporting" -Name "DisableEnhancedNotifications" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableIOAVProtection" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowBehaviorMonitoring" -Value 2 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowCloudProtection" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowRealtimeMonitoring" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" -Name "Notification_Suppress" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" -Name "UILockdown" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" -Name "DisableNotifications" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontReportInfectionInformation" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows Security Health\State" -Name "AppAndBrowser_EdgeSmartScreenOff" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "SmartScreenEnabled" -Value "Off" -Type String
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "PreventOverride" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "PreventOverride" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Edge\SmartScreenEnabled" -Name "(default)" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Edge\SmartScreenEnabled" -Name "(default)" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled" -Name "(default)" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Edge\SmartScreenPuaEnabled" -Name "(default)" -Value 0 -Type DWord -Force
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\System" -Name "ShellSmartScreenLevel" -Value 0 -Type DWord -Force
			@("SecurityHealthService", "WinDefend", "WdNisSvc", "WdNisDrv", "WdBoot", "WdFilter", "Sense", "webthreatdefsvc", "webthreatdefusersvc") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
			@("HKLM:\WIM_HKLM_SOFTWARE\Classes\*\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\EPP",
				"HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\WMI\AutoLogger\DefenderApiLogger", "HKLM:\WIM_HKLM_SYSTEM\$CCS\Control\WMI\AutoLogger\DefenderAuditLogger") | Purge
			Remove-KeyProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth"
			If ($InstallInfo.Build -ge '17763')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControlEnabled" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControl" -Value "Anywhere" -Type String
			}
			[Void]$Visibility.Append('windowsdefender;')
			$DynamicParams.SecHealthUI = $true
			Log $OptimizeData.DisableDefender
			Clear-Host
		}
		If ($Visibility.Length -gt 5)
		{
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
			RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
		}
		If($RemovedPackages."Microsoft.Windows.Search") {
			$DynamicParams.RemovedWindowsSearchPackage = $true
		}
		RegHives -Unload
		If ($DynamicParams.BioEnrollment -and (Get-WindowsCapability -Path $InstallMount -Name *Hello* -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Installed))
		{
			Try
			{
				Get-WindowsCapability -Path $InstallMount -Name *Hello* -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Installed | ForEach-Object -Process {
					$RemoveBiometricCapability = @{
						Path             = $InstallMount
						Name             = $PSItem.Name
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.RemovingBiometricCapability -f $PSItem.Name)
					[Void](Remove-WindowsCapability @RemoveBiometricCapability)
				}
			}
			Catch
			{
				Log $OptimizeData.FailedRemovingBiometricCapability -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}
		If ($DynamicParams.SecHealthUI -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName Windows-Defender-Default-Definitions -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Enabled))
		{
			Try
			{
				$DisableDefenderOptionalFeature = @{
					Path             = $InstallMount
					FeatureName      = 'Windows-Defender-Default-Definitions'
					Remove           = $true
					NoRestart        = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log $OptimizeData.DisablingDefenderOptionalFeature
				[Void](Disable-WindowsOptionalFeature @DisableDefenderOptionalFeature)
			}
			Catch
			{
				Log $OptimizeData.FailedDisablingDefenderOptionalFeature -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}
		#endregion Removed Package Clean-up

		#region Import Custom App Associations
		If (Test-Path -Path $OptimizeOffline.CustomAppAssociations)
		{
			Log $OptimizeData.ImportingCustomAppAssociations
			$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Import-DefaultAppAssociations:"{1}" /ScratchDir:"{2}" /LogPath:"{3}" /LogLevel:1' -f $InstallMount, $OptimizeOffline.CustomAppAssociations, $ScratchFolder, $DISMLog)
			If ($RET -ne 0) { Log $OptimizeData.FailedImportingCustomAppAssociations -Type Error; Start-Sleep 3 }
		}
		#endregion Import Custom App Associations

		#region Windows Capability and Cabinet File Package Removal
		If ($Capabilities -in $AllowedRemovalOptions)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Capabilities."
			$WindowsCapabilities = Get-CapabilityPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog

			If ($WindowsCapabilities)
			{
				Try
				{
					$capabilitiesToRemove = [System.Collections.ArrayList]@()

					Switch ($PSBoundParameters.Capabilities)
					{
						'Select'
						{
							If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
								$PSCmdlet.WriteWarning(("Capabilities Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
								Break
							}
							$capabilitiesToRemove = $WindowsCapabilities | Out-GridView -Title "Remove Windows Capabilities." -PassThru
							Break
						}
						'Whitelist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.CapabilitiesList)
							{
								$Names = Get-Content -Path $OptimizeOffline.Lists.CapabilitiesList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty Name
								$WindowsCapabilities | ForEach-Object -Process {
									$ToRemove = $true
									Foreach($Name in $Names){
										If ($PSItem.Name -eq $Name -or ($Name -match "\*" -and $PSItem.Name -like $Name)){ $ToRemove = $false; Break }
									}
									If($ToRemove){ [void]$capabilitiesToRemove.Add($PSItem) }
								}
							}
							Break
						}
						'Blacklist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.CapabilitiesList)
							{
								$Names = Get-Content -Path $OptimizeOffline.Lists.CapabilitiesList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty Name
								$WindowsCapabilities | ForEach-Object -Process {
									Foreach($Name in $Names){
										If ($PSItem.Name -eq $Name -or ($Name -match "\*" -and $PSItem.Name -like $Name)){ [void]$capabilitiesToRemove.Add($PSItem); Break }
									}
								}
							}
							Break
						}
						'All' { $capabilitiesToRemove = $WindowsCapabilities }
					}

					$capabilitiesToRemove | ForEach-Object -Process {
						$RemoveCapabilityParams = @{
							Path             = $InstallMount
							Name             = $PSItem.Name
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.RemovingWindowsCapability -f $PSItem.Name)
						# Permanent capabilities in certain editions (e.g. 0x800f0825) — skip gracefully.
						Try { [Void](Remove-WindowsCapability @RemoveCapabilityParams) }
						Catch { Log ('Skipped Windows Capability (cannot be removed from this image): {0}' -f $RemoveCapabilityParams.Name) -Type Error -ErrorRecord $Error[0] }
					}

					$DynamicParams.Capabilities = $($capabilitiesToRemove.Count -gt 0)
				}
				Catch
				{
					Log $OptimizeData.FailedRemovingWindowsCapabilities -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}

		If ($Packages -in $AllowedRemovalOptions)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Packages."
			$WindowsPackages = Get-OtherWindowsPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog

			If ($WindowsPackages)
			{
				$packagesToRemove = [System.Collections.ArrayList]@()
				Try
				{
					Switch ($PSBoundParameters.Packages) {
						'Select'
						{
							If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
								$PSCmdlet.WriteWarning(("Packages Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
								Break
							}
							$packagesToRemove = $WindowsPackages | Out-GridView -Title "Remove Windows Packages." -PassThru
							Break
						}
						'Whitelist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.PackagesList)
							{
								$PackageNames = Get-Content -Path $OptimizeOffline.Lists.PackagesList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty PackageName
								$WindowsPackages | ForEach-Object -Process {
									$ToRemove = $true
									Foreach($PackageName in $PackageNames){
										If ($PSItem.PackageName -eq $PackageName -or ($PackageName -Match "\*" -and $PSItem.PackageName -like $PackageName)) { $ToRemove = $false; Break }
									}
									If($ToRemove){ [void]$packagesToRemove.Add($PSItem) }
								}
							}
							Break
						}
						'Blacklist'
						{
							If (Test-Path -Path $OptimizeOffline.Lists.PackagesList)
							{
								$PackageNames = Get-Content -Path $OptimizeOffline.Lists.PackagesList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty PackageName
								$WindowsPackages | ForEach-Object -Process {
									Foreach($PackageName in $PackageNames){
										If ($PSItem.PackageName -eq $PackageName -or ($PackageName -Match "\*" -and $PSItem.PackageName -like $PackageName)) { [void]$packagesToRemove.Add($PSItem); Break }
									}
								}
							}
							Break
						}
						'All' { $packagesToRemove = $WindowsPackages }
					}

					$packagesToRemove | ForEach-Object -Process {
						$RemovePackageParams = @{
							Path             = $InstallMount
							PackageName      = $PSItem.PackageName
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.RemovingWindowsPackage -f $PSItem.PackageName)
						Try { [Void](Remove-WindowsPackage @RemovePackageParams) }
						Catch { Log ('Skipped Windows Package (cannot be removed from this image): {0}' -f $PSItem.PackageName) -Type Error -ErrorRecord $Error[0] }
					}
					$DynamicParams.Packages = $($packagesToRemove.Count -gt 0)
				}
				Catch
				{
					Log $OptimizeData.FailedRemovingWindowsPackages -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Windows Capability and Cabinet File Package Removal

		#region Disable Unsafe Optional Features
		ForEach ($Feature In @('SMB1Protocol', 'MicrosoftWindowsPowerShellV2Root'))
		{
			If (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName $Feature -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Enabled)
			{
				Try
				{
					$DisableOptionalFeatureParams = @{
						Path             = $InstallMount
						FeatureName      = $Feature
						Remove           = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.DisablingUnsafeOptionalFeature -f $Feature)
					[Void](Disable-WindowsOptionalFeature @DisableOptionalFeatureParams)
				}
				Catch
				{
					Log ($OptimizeData.FailedDisablingUnsafeOptionalFeature -f $Feature) -Type Error -ErrorRecord $Error[0]
					# Do not abort the whole run for a single feature failure.
				}
			}
		}
		#endregion Disable Unsafe Optional Features

		#region Disable/Enable Optional Features
		If ($FeaturesToDisable -in $AllowedRemovalOptions)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Disable Optional Features."
			$EnabledFeatures = Get-OptionalEnabledFeatures -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog

			If ($EnabledFeatures)
			{
				$FeaturesToDisableList = [System.Collections.ArrayList]@()
				Switch ($PSBoundParameters.FeaturesToDisable) {
					'Select'
					{
						If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
							$PSCmdlet.WriteWarning(("FeaturesToDisable Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
							Break
						}
						$FeaturesToDisableList = $EnabledFeatures | Out-GridView -Title "Disable Optional Features." -PassThru
						Break
					}
					"List"
					{
						If (Test-Path -Path $OptimizeOffline.Lists.FeaturesToDisableList)
						{
							$JSON = Get-Content -Path $OptimizeOffline.Lists.FeaturesToDisableList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
							$EnabledFeatures | ForEach-Object -Process {
								If ($PSItem.FeatureName -in $JSON.FeatureName) { [void]$FeaturesToDisableList.Add($PSItem) }
							}
						}
						Break
					}
					'All' { $FeaturesToDisableList = $EnabledFeatures }
				}
				Try
				{
					$FeaturesToDisableList | ForEach-Object -Process {
						$DisableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							Remove           = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.DisablingOptionalFeature -f $PSItem.FeatureName)
						Try { [Void](Disable-WindowsOptionalFeature @DisableFeatureParams) }
						Catch { Log ('Skipped Optional Feature (cannot be disabled): {0}' -f $PSItem.FeatureName) -Type Error -ErrorRecord $Error[0] }
					}
					$DynamicParams.DisabledOptionalFeatures = $($FeaturesToDisableList.Count -gt 0)
				}
				Catch
				{
					Log $OptimizeData.FailedDisablingOptionalFeatures -Type Error -ErrorRecord $Error[0]
					# Continue — individual feature failures are non-fatal on 24H2.
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		If ($FeaturesToEnable -in $AllowedRemovalOptions){
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Enable Optional Features."
			$DisabledFeatures = Get-OptionalDisabledFeatures -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog

			If ($DisabledFeatures)
			{
				$FeaturesToEnableList = [System.Collections.ArrayList]@()
				Switch ($PSBoundParameters.FeaturesToEnable) {
					'Select'
					{
						If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
							$PSCmdlet.WriteWarning(("FeaturesToEnable Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
							Break
						}
						$FeaturesToEnableList = $DisabledFeatures | Out-GridView -Title "Enable Optional Features." -PassThru
						Break
					}
					"List"
					{
						If (Test-Path -Path $OptimizeOffline.Lists.FeaturesToEnableList)
						{
							$JSON = Get-Content -Path $OptimizeOffline.Lists.FeaturesToEnableList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
							$DisabledFeatures | ForEach-Object -Process {
								If ($PSItem.FeatureName -in $JSON.FeatureName) { [void]$FeaturesToEnableList.Add($PSItem) }
							}
						}
						Break
					}
					"All" { $FeaturesToEnableList = $DisabledFeatures }
				}

				Try
				{
					$FeaturesToEnableList | ForEach-Object -Process {
						$EnableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							All              = $true
							LimitAccess      = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.EnablingOptionalFeature -f $PSItem.FeatureName)
						Try { [Void](Enable-WindowsOptionalFeature @EnableFeatureParams) }
						Catch { Log ('Skipped Optional Feature (cannot be enabled): {0}' -f $PSItem.FeatureName) -Type Error -ErrorRecord $Error[0] }
					}
					$DynamicParams.EnabledOptionalFeatures = $($FeaturesToEnableList.Count -gt 0)
				}
				Catch
				{
					Log $OptimizeData.FailedEnablingOptionalFeatures -Type Error -ErrorRecord $Error[0]
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Disable/Enable Optional Features

		#region Disable Windows Services
		if ($PSBoundParameters.Services -in $AllowedRemovalOptions){
			$ServicesToRemove = [System.Collections.ArrayList]@()
			$ServicesToRemoveNames = @{}
			$StartValues = @(0,1,2,3,4)

			Clear-Host
			$Host.UI.RawUI.WindowTitle = $OptimizeData.ServicesModifying

			Try{
				RegHives -Load

				Switch($PSBoundParameters.Services){
					"List"
					{
						$JSON = Get-Content -Path $OptimizeOffline.Lists.ServicesList -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
						$JSON.Services | ForEach-Object -Process {
							If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)")
							{
								$FolderKeys = Get-ItemProperty -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem)"
								If($null -ne $FolderKeys.Start){
									[void]$ServicesToRemove.Add(@{
										name = $PSItem
										start = 4
									})
								}
							}
						}
					}
					"Advanced"
					{
						$JSON = Get-Content -Path $OptimizeOffline.Lists.ServicesAdvanced -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
						$JSON.Services | ForEach-Object -Process {
							If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem.name)")
							{
								$FolderKeys = Get-ItemProperty -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem.name)"
								If($null -eq $PSItem.start) { $PSItem.start = 4 }
								If($null -ne $FolderKeys.Start -and [int]$PSItem.start -in $StartValues){
									[void]$ServicesToRemove.Add($PSItem)
								}
							}
						}
					}
					"Select"
					{
						If ($InteractiveGridView -and -not $InteractiveGridView.Available) {
							$PSCmdlet.WriteWarning(("Services Select unavailable: {0} Skipping.") -f $InteractiveGridView.Reason)
							Break
						}
						$ServicesToRemove = Get-ImageServices | Out-GridView -PassThru -Title $OptimizeData.ChooseServicesTitle
					}
				}

				$ServicesToRemove | ForEach-Object -Process {
					$Start = If ($PSBoundParameters.Services -eq "Select") {4} Else {[Int]$PSItem.start}
					Log "$($OptimizeData.ServiceModifying): $($PSItem.name), Start: $($OptimizeOffline.ServicesStartLabels[$Start])"
					RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\$($PSItem.name)" -Name "Start" -Type DWord -Value $Start
					$ServicesToRemoveNames[$PSItem.name] = $Start
					Start-Sleep 1
				}
				$DynamicParams.DisabledWindowsServices = $($ServicesToRemove.Count -gt 0)

				# Delivery Optimization bypass when DoSvc is disabled.
				If ($null -ne $ServicesToRemoveNames['DoSvc'] -and $ServicesToRemoveNames['DoSvc'] -eq 4){
					Log $OptimizeData.DeliveryOptimizationBypass
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 100
					Start-Sleep 1
				}
				RegHives -Unload
			} Catch {
				Log $OptimizeData.ServicesRemovalFailed -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}

			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		#endregion Disable Windows Services

		#region DeveloperMode Integration
		If ($DeveloperMode.IsPresent) {
			Invoke-OptimizeDeveloperMode -InstallMount $InstallMount -ScratchFolder $ScratchFolder -DISMLog $DISMLog -WorkFolder $WorkFolder -OptimizeOffline $OptimizeOffline -DynamicParams $DynamicParams
		}
		#endregion DeveloperMode Integration

#region Windows Store Integration
Invoke-OptimizeWindowsStore `
    -InstallMount    $InstallMount `
    -ScratchFolder   $ScratchFolder `
    -DISMLog         $DISMLog `
    -OptimizeOffline $OptimizeOffline `
    -DynamicParams   $DynamicParams `
    -AppxPackages    $AppxPackages `
    -WindowsStore:$WindowsStore.IsPresent
#endregion Windows Store Integration

		#region Microsoft Edge Integration
		If ($MicrosoftEdge.IsPresent)
		{
			# Fork: 24H2+ has Edge Chromium bundled — no-op unless explicit CAB is provided.
			If ($DynamicParams.LTSC -and (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter Microsoft-Windows-Internet-Browser-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *Internet-Browser*))
			{
				Try
				{
					Log $OptimizeData.IntegratingMicrosoftEdge
					@((GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
						(GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab")) |
						ForEach-Object -Process { [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $PSItem -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop) }
					$DynamicParams.MicrosoftEdge = $true
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingMicrosoftEdge -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
			ElseIf (!$DynamicParams.LTSC -and (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter Microsoft-Windows-Chromium-Browser-Package*.cab) -and !(Get-ChildItem -Path (GetPath -Path $InstallMount -Child "Windows\WinSxS\*firsttimeinstaller*\MicrosoftEdgeStandaloneInstaller.exe") -File -Force -ErrorAction SilentlyContinue))
			{
				# Fork: dynamic CAB discovery — no hardcoded UBR.
				$EdgeCab = Get-ChildItem -Path $OptimizeOffline.MicrosoftEdge -Filter "Microsoft-Windows-Chromium-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).*.cab" -File |
					Sort-Object -Property Name -Descending | Select-Object -First 1
				If ($EdgeCab) {
					Log $OptimizeData.IntegratingMicrosoftEdgeChromium
					If (!$RemovedSystemApps.'Microsoft.MicrosoftEdge')
					{
						RegHives -Load
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "Allowsxs" -Value 1 -Type DWord
						RegHives -Unload
					}
					Try
					{
						[Void](Add-WindowsPackage -Path $InstallMount -PackagePath $EdgeCab.FullName -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop)
						$DynamicParams.MicrosoftEdgeChromium = $true
					}
					Catch
					{
						Log $OptimizeData.FailedIntegratingMicrosoftEdgeChromium -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				} Else {
					Log ("Edge CAB for build {0} not found — skipping integration." -f $InstallInfo.Build) -Type Warning
				}
			}
		}
		#endregion Microsoft Edge Integration

		#region Microsoft Edge Policy Integration
		If ($DynamicParams.MicrosoftEdge -or $DynamicParams.MicrosoftEdgeChromium)
		{
			If (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter MicrosoftEdgePolicies.wim)
			{
				Try
				{
					$ExpandEdgePoliciesParams = @{
						ImagePath        = ('{0}\MicrosoftEdgePolicies.wim' -f $OptimizeOffline.MicrosoftEdge)
						Index            = 1
						ApplyPath        = $InstallMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.IntegratingMicrosoftEdgePolicies
					[Void](Expand-WindowsImage @ExpandEdgePoliciesParams)
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingMicrosoftEdgePolicies -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
			RegHives -Load
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "DisableEdgeDesktopShortcutCreation" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\BooksLibrary" -Name "EnableExtendedBooksTelemetry" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\BooksLibrary" -Name "EnableExtendedBooksTelemetry" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "ShowSearchSuggestionsGlobal" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "IE10TourShown" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "DisallowDefaultBrowserPrompt" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FlipAhead" -Name "FPEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FirstRun" -Name "LastFirstRunVersionDelivered" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\ServiceUI" -Name "EnableCortana" -Value 0 -Type DWord
			If ($DynamicParams.LTSC -and $DynamicParams.SecHealthUI)
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
			}
			If ($DynamicParams.MicrosoftEdgeChromium)
			{
				$EdgeAppPath = (GetPath -Path $InstallMount -Child 'Program Files (x86)\Microsoft\Edge\Application') | Create -PassThru
				[IO.File]::WriteAllText((GetPath -Path $EdgeAppPath.FullName -Child master_preferences), (@'
{"distribution":{"system_level":true,"do_not_create_desktop_shortcut":true,"do_not_create_quick_launch_shortcut":true,"do_not_create_taskbar_shortcut":true}}
'@).Trim(), [Text.UTF8Encoding]::New($true))
				$Base64String = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes({ Get-ChildItem -Path @("HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components") -Recurse | Get-ItemProperty | Select-Object -Property PSPath, StubPath | Where-Object -Property StubPath -Match configure-user-settings | ForEach-Object -Process { Remove-Item -Path $PSItem.PSPath -Force }; Get-ChildItem -Path "$Env:SystemDrive\Users\*\Desktop" -Filter *lnk -Recurse | Where-Object -Property Name -Like *Edge* | Remove-Item -Force }))
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "EdgeCleanup" -Value "%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -EncodedCommand $Base64String" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcutDefault" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcutDefault" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord
				If ($InstallInfo.Build -gt '19041' -or ($InstallInfo.Build -eq '19041' -and (Get-ItemPropertyValue -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name UBR -ErrorAction Ignore) -ge 1023)) {
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord
				}
			}
			RegHives -Unload
		}
		#endregion Microsoft Edge Policy Integration

		# Win32 Calculator Integration removed (Win10-era only).

		#region Data Deduplication Integration (per-language, dynamic)
		Invoke-OptimizeDataDedup `
			-InstallMount $InstallMount `
			-ScratchFolder $ScratchFolder `
			-DISMLog $DISMLog `
			-CCS $CCS `
			-DedupFolder $OptimizeOffline.Dedup `
			-DynamicParams $DynamicParams `
			-OptimizeData $OptimizeData
		#endregion Data Deduplication Integration

		# DaRT 10 Integration removed (Win10-era only).

		#region Apply Optimized Registry Settings
		If ($Registry.IsPresent)
		{
			If (Test-Path -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1"))
			{
				Set-RegistryProperty
			}
			Else
			{
				Log ($OptimizeData.MissingRequiredRegistryData -f (GetPath -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1") -Split Leaf)) -Type Error
				Start-Sleep 3
			}
		}
		#endregion Apply Optimized Registry Settings

		#region Additional Content Integration
		If ($Additional.ContainsValue($true))
		{
			If (($Additional.Setup -or $Additional.RemoveWindowsAI -or $Additional.RemoveOneDrive -or $Additional.DisableDefender) -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Setup -Child *)))
			{
				Try
				{
					Log $OptimizeData.ApplyingSetupContent
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Create
					Get-ChildItem -Path $OptimizeOffline.Setup -Exclude RebootRecovery.png, RefreshExplorer.png, README.md, RWAI_Cleanup.ps1 | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') -Recurse -Force -ErrorAction Stop
					If ($Additional.RemoveWindowsAI)   { New-Item -Path (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts\RemoveWindowsAI.enabled')   -ItemType File -Force | Out-Null }
					If ($Additional.RemoveOneDrive)    { New-Item -Path (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts\RemoveOneDrive.enabled')    -ItemType File -Force | Out-Null }
					If ($Additional.DisableDefender)   { New-Item -Path (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts\DisableDefender.enabled')   -ItemType File -Force | Out-Null }
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingSetupContent -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Purge
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.DisableDefender)
			{
				Try
				{
					If (!(Test-Path -LiteralPath $OptimizeOffline.DisableDefender -PathType Container)) { Throw 'The bundled Disable-Defender utility directory is missing.' }
					Log 'Staging the optional Defender disable/restore utility and first-sign-in prompt.'
					$DefenderUtilityPath = GetPath -Path $InstallMount -Child 'Users\Public\Desktop\Disable-Defender'
					$DefenderUtilityPath | Create
					Get-ChildItem -LiteralPath $OptimizeOffline.DisableDefender -Force | Copy-Item -Destination $DefenderUtilityPath -Recurse -Force -ErrorAction Stop
					Copy-Item -LiteralPath (GetPath -Path $OptimizeOffline.DisableDefender -Child 'Start-DisableDefender.ps1') -Destination (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') -Force -ErrorAction Stop
				}
				Catch
				{
					Log 'Failed staging the optional Defender disable/restore utility.' -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Wallpaper -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *)))
			{
				Try
				{
					Log $OptimizeData.ApplyingWallpaper
					Get-ChildItem -Path $OptimizeOffline.Wallpaper -Directory | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Recurse -Force -ErrorAction Stop
					Get-ChildItem -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *) -Include *.jpg, *.png, *.bmp, *.gif -File | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Force -ErrorAction Stop
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingWallpaper -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.SystemLogo -and (Test-Path -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp)))
			{
				Try
				{
					Log $OptimizeData.ApplyingSystemLogo
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp) -Destination (GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') -Recurse -Force -ErrorAction Stop
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingSystemLogo -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Purge
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.LockScreen -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LockScreen -Child *.jpg)))
			{
				Set-LockScreen
				Start-Sleep 3
			}
			If ($Additional.RegistryTemplates -and (Test-Path -Path (GetPath -Path $OptimizeOffline.RegistryTemplates -Child *.reg)))
			{
				Import-Registry -Path $OptimizeOffline.RegistryTemplates
				Start-Sleep 3
			}
			If ($Additional.LayoutModification -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.xml)))
			{
				Try
				{
					Log $OptimizeData.ApplyingLayoutModification
					Copy-Item -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.xml) -Destination (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') -Force -ErrorAction Stop
					$DynamicParams.LayoutModification = $true
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingLayoutModification -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.LayoutModification -and $InstallInfo.Build -ge "22000" -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.json)))
			{
				Try
				{
					Log $OptimizeData.ApplyingLayoutModification
					Copy-Item -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.json) -Destination (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json') -Force -ErrorAction Stop
					$DynamicParams.LayoutModification = $true
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingLayoutModification -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Unattend -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml)))
			{
				Try
				{
					Unblock-File -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml)
					Log $OptimizeData.ApplyingAnswerFile
					$ApplyUnattendParams = @{
						UnattendPath     = '{0}\unattend.xml' -f $OptimizeOffline.Unattend
						Path             = $InstallMount
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					[Void](Use-WindowsUnattend @ApplyUnattendParams)
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml) -Destination (GetPath -Path $InstallMount -Child 'Windows\Panther') -Force
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingAnswerFile -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Purge
					Start-Sleep 3
				}
			}
			If ($Additional.Drivers)
			{
				Get-ChildItem -Path $OptimizeOffline.Drivers -Recurse -Force | ForEach-Object -Process {
					Unblock-File -Path $PSItem.FullName
					Set-ItemProperty -Path $PSItem.FullName -Name IsReadOnly -Value $false -ErrorAction Ignore
				}
				If (Get-ChildItem -Path $OptimizeOffline.InstallDrivers -Include *.inf -Recurse -Force)
				{
					Try
					{
						$InstallDriverParams = @{
							Path             = $InstallMount
							Driver           = $OptimizeOffline.InstallDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $InstallInfo.Name)
						[Void](Add-WindowsDriver @InstallDriverParams)
						$DynamicParams.InstallImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
				If ($DynamicParams.BootImage -and (Get-ChildItem -Path $OptimizeOffline.BootDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$BootDriverParams = @{
							Path             = $BootMount
							Driver           = $OptimizeOffline.BootDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $BootInfo.Name)
						[Void](Add-WindowsDriver @BootDriverParams)
						$DynamicParams.BootImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
				If ($DynamicParams.RecoveryImage -and (Get-ChildItem -Path $OptimizeOffline.RecoveryDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$RecoveryDriverParams = @{
							Path             = $RecoveryMount
							Driver           = $OptimizeOffline.RecoveryDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $RecoveryInfo.Name)
						[Void](Add-WindowsDriver @RecoveryDriverParams)
						$DynamicParams.RecoveryImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
			}
			If ($Additional.NetFx3 -and (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child 'sources\sxs') -Filter *netfx3*.cab) -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName NetFx3 -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ DisabledWithPayloadRemoved))
			{
				Try
				{
					$EnableNetFx3Params = @{
						Path             = $InstallMount
						FeatureName      = 'NetFx3'
						Source           = '{0}\sources\sxs' -f $ISOMedia.FullName
						All              = $true
						LimitAccess      = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.EnablingNetFx3
					[Void](Enable-WindowsOptionalFeature @EnableNetFx3Params)
					$DynamicParams.NetFx3 = $true
				}
				Catch
				{
					Log $OptimizeData.FailedEnablingNetFx3 -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
		}
		#endregion Additional Content Integration

		#region Selective Registry
		Get-ChildItem -Path $OptimizeOffline.SelectiveRegistry -Filter *.ps1 -Recurse | ForEach-Object -Process {
			& $_.FullName
		}
		#endregion Selective Registry

		#region Custom Registry
		If (Test-Path -Path $OptimizeOffline.CustomRegistry)
		{
			Import-Registry -Path $OptimizeOffline.CustomRegistry
			Start-Sleep 3
		}
		#endregion Custom Registry

		#region Component Store Clean-up
		If ($ComponentCleanup.IsPresent)
		{
			If (!(Test-Path -Path (GetPath -Path $InstallMount -Child 'Windows\WinSxS\pending.xml')))
			{
				Log ($OptimizeData.ComponentStoreCleanup -f $InstallInfo.Name)
				If ($InstallInfo.Build -ge '18362') { $RegClean = 3 } Else { $RegClean = 0 }
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Configuration" -Name "DisableResetbase" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Configuration" -Name "SupersededActions" -Value $RegClean -Type DWord
				RegHives -Unload
				$CleanupLog = (GetPath -Path $LogFolder -Child ComponentCleanup.log)
				Try
				{
					$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Cleanup-Image /StartComponentCleanup /ScratchDir:"{1}" /LogPath:"{2}" /LogLevel:1' -f $InstallMount, $ScratchFolder, $CleanupLog) -ErrorAction Stop
					If ($RET -eq 0) { $DynamicParams.ComponentCleanup = $true }
					Else { Throw }
				}
				Catch
				{
					Log ($OptimizeData.FailedComponentStoreCleanup -f $InstallInfo.Name) -Type Error
				}
				Finally
				{
					$CleanupLog | Purge -ErrorAction Ignore
				}
			}
			Else
			{
				Log $OptimizeData.ComponentStorePendingInstallations
			}
		}
		#endregion Component Store Clean-up

		#region Start Menu Clean-up (legacy non-24H2 path only)
		If (!$DynamicParams.LayoutModification -and $InstallInfo.Build -le '19044')
		{
			$LayoutTemplate = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupsColumnCount="2" StartTileGroupCellWidth="6" FullScreenStart="false" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6">
                <start:Group Name="$($InstallInfo.Name)">
                    <start:DesktopApplicationTile Size="2x2" Column="0" Row="0" DesktopApplicationID="Microsoft.Windows.Computer" />
                    <start:DesktopApplicationTile Size="2x2" Column="2" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\Master Control Panel.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="1" DesktopApplicationID="Microsoft.Windows.AdministrativeTools" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="1" DesktopApplicationID="Microsoft.Windows.Shell.RunDialog" />
                </start:Group>
            </defaultlayout:StartLayout>
        </StartLayoutCollection>
    </DefaultLayoutOverride>
    <CustomTaskbarLayoutCollection PinListPlacement="Replace">
        <defaultlayout:TaskbarLayout>
            <taskbar:TaskbarPinList>
                <taskbar:DesktopApp DesktopApplicationLinkPath="#leaveempty"/>
            </taskbar:TaskbarPinList>
        </defaultlayout:TaskbarLayout>
    </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
			Try
			{
				Log $OptimizeData.CleanupStartMenu
				$MCPShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
				$MCPShortcut = $MCPShell.CreateShortcut((GetPath -Path $InstallMount -Child 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\System Tools\Master Control Panel.lnk'))
				$MCPShortcut.TargetPath = "%SystemRoot%\explorer.exe"
				$MCPShortcut.Arguments = "shell:::{ED7BA470-8E54-465E-825C-99712043E01C}"
				$MCPShortcut.WorkingDirectory = "%SystemRoot%"
				$MCPShortcut.Description = "Windows Control Panel All Tasks."
				$MCPShortcut.IconLocation = "%SystemRoot%\System32\imageres.dll,-27"
				$MCPShortcut.Save()
			}
			Catch
			{
				$LayoutTemplate = $LayoutTemplate.Replace('Master Control Panel.lnk', 'Control Panel.lnk')
			}
			Finally
			{
				[Void][Runtime.InteropServices.Marshal]::ReleaseComObject($MCPShell)
			}
			If ($RemovedSystemApps.'Microsoft.Windows.FileExplorer') { $LayoutTemplate = $LayoutTemplate.Replace('UWP File Explorer.lnk', 'File Explorer.lnk') }
			Else
			{
				Try
				{
					$UWPShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
					$UWPShortcut = $UWPShell.CreateShortcut((GetPath -Path $InstallMount -Child 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk'))
					$UWPShortcut.TargetPath = "%SystemRoot%\explorer.exe"
					$UWPShortcut.Arguments = "shell:AppsFolder\c5e2524a-ea46-4f67-841f-6a9465d9d515_cw5n1h2txyewy!App"
					$UWPShortcut.WorkingDirectory = "%SystemRoot%"
					$UWPShortcut.Description = "UWP File Explorer"
					$UWPShortcut.Save()
				}
				Catch
				{
					$LayoutTemplate = $LayoutTemplate.Replace('UWP File Explorer.lnk', 'File Explorer.lnk')
				}
				Finally
				{
					[Void][Runtime.InteropServices.Marshal]::ReleaseComObject($UWPShell)
				}
			}
			Try
			{
				$LayoutTemplate | Out-File -FilePath (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') -Encoding UTF8 -Force -ErrorAction Stop
			}
			Catch
			{
				Log $OptimizeData.FailedCleanupStartMenu -Type Error
			}
			Finally
			{
				Start-Sleep 3; Clear-Host
			}
		}
		#endregion Start Menu Clean-up

		#region Disable W11 boot image HW checks and enable local account support
		If ($InstallInfo.Build -ge '22000') {
			RegHives -Load
			# Local account / OOBE bypass.
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "BypassNRO" -Value 1 -Type DWord -Force

			# Apply hardware-check bypass only when the Setup boot.wim is actually mounted.
			If ($DynamicParams.BootImage -and (Test-Path -Path $BootMount)) {
				# Mount BOOT registry hive — note: requires a loaded Boot hive via RegHives or direct reg.exe load.
				# Using reg.exe here to be explicit and 24H2-safe.
				$BootHivePath = GetPath -Path $BootMount -Child 'Windows\System32\config\SYSTEM'
				if (Test-Path -Path $BootHivePath) {
					$null = StartExe $REG -Arguments ('LOAD HKLM\BOOT_HKLM_SYSTEM "{0}"' -f $BootHivePath)
					Try {
						@('BypassCPUCheck','BypassRAMCheck','BypassSecureBootCheck','BypassStorageCheck','BypassTPMCheck') | ForEach-Object -Process {
							RegKey -Path "HKLM:\BOOT_HKLM_SYSTEM\Setup\LabConfig" -Name $PSItem -Type DWord -Value 1
						}
					} Finally {
						$null = StartExe $REG -Arguments 'UNLOAD HKLM\BOOT_HKLM_SYSTEM'
					}
				}
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Type DWord -Value 1

				RegKey -Path "HKLM:\WIM_HKCU\Control Panel\UnsupportedHardwareNotificationCache" -Name "SV1" -Type DWord -Value 0
				RegKey -Path "HKLM:\WIM_HKCU\Control Panel\UnsupportedHardwareNotificationCache" -Name "SV2" -Type DWord -Value 0
				RegKey -Path "HKLM:\WIM_HKU_DEFAULT\Control Panel\UnsupportedHardwareNotificationCache" -Name "SV1" -Type DWord -Value 0
				RegKey -Path "HKLM:\WIM_HKU_DEFAULT\Control Panel\UnsupportedHardwareNotificationCache" -Name "SV2" -Type DWord -Value 0

				if (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter appraiserres.dll -File) {
					Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter appraiserres.dll -File | Rename-Item -NewName appraiserres.dll.bak
				}
			}
			RegHives -Unload
		}
		#endregion Disable W11 boot image HW checks

		#region Create Package Summary
		@('DeveloperMode', 'WindowsStore', 'MicrosoftEdge', 'MicrosoftEdgeChromium', 'DataDeduplication', 'InstallImageDrivers', 'BootImageDrivers', 'RecoveryImageDrivers', 'NetFx3') |
			ForEach-Object -Process { If ($DynamicParams.ContainsKey($PSItem)) { $DynamicParams.PackageSummary = $true } }
		If ($DynamicParams.PackageSummary)
		{
			Log $OptimizeData.CreatingPackageSummaryLog
			$PackageLog = New-Item -Path $LogFolder -Name PackageSummary.log -ItemType File -Force
			If ($DynamicParams.WindowsStore) {
				# Fork (24H2): $AppxPackages — это снимок ДО интеграции Store.
				# Пересчитываем Appx на актуальном образе, чтобы в сводке были
				# и изначальные пакеты, и только что интегрированный Store.
				$AppxPackagesNow = Get-AppxPackages -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog
				"`t`t`t`tIntegrated Provisioned App Packages", ($AppxPackagesNow | Select-Object -Property PackageName) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force
			}
			If ($DynamicParams.DeveloperMode -or $DynamicParams.MicrosoftEdge -or $DynamicParams.MicrosoftEdgeChromium -or $DynamicParams.DataDeduplication -or $DynamicParams.NetFx3) {
				"`t`t`t`tIntegrated Windows Packages", (
					Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 |
						Where-Object { $PSItem.PackageName -like "*DeveloperMode*" -or $PSItem.PackageName -like "*Internet-Browser*" -or $PSItem.PackageName -like "*Chromium-Browser*" -or $PSItem.PackageName -like "*Windows-FileServer-ServerCore*" -or $PSItem.PackageName -like "*Windows-Dedup*" -or $PSItem.PackageName -like "*Windows-FileServer-Core*" -or $PSItem.PackageName -like "*NetFx3*" } |
						Select-Object -Property PackageName, PackageState
				) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force
			}
			If ($DynamicParams.InstallImageDrivers)  { "`t`t`t`tIntegrated Drivers (Install)",  (Get-WindowsDriver -Path $InstallMount  -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.BootImageDrivers)     { "`t`t`t`tIntegrated Drivers (Boot)",     (Get-WindowsDriver -Path $BootMount     -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.RecoveryImageDrivers) { "`t`t`t`tIntegrated Drivers (Recovery)", (Get-WindowsDriver -Path $RecoveryMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
		}
		#endregion Create Package Summary

		#region Image Finalization
		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).ImageHealthState -eq 'Healthy')
		{
			Log $OptimizeData.PostOptimizedImageHealthHealthy
			@"
This $($InstallInfo.Name) installation was optimized with $($OptimizeOffline.BaseName) version $($ManifestData.ModuleVersion)
on $(Get-Date -UFormat "%m/%d/%Y at %r")
"@ | Out-File -FilePath (GetPath -Path $InstallMount -Child Optimize-Offline.txt) -Encoding Unicode -Force
			If((Test-Path -Path "$($OptimizeOffline.Assets)\windows.ico")) {
				Unblock-File -Path "$($OptimizeOffline.Assets)\windows.ico"
				Set-ItemProperty -Path "$($OptimizeOffline.Assets)\windows.ico" -Name IsReadOnly -Value $false
				Copy-Item -Path (Get-Item -Path "$($OptimizeOffline.Assets)\windows.ico") -Destination $InstallMount
				"[Autorun]
Icon=setup.ico" | Out-File "$($InstallMount)\Autorun.inf" -Encoding ascii
				(Get-Item -Path "$($InstallMount)\windows.ico").Attributes += 'Hidden'
				(Get-Item -Path "$($InstallMount)\Autorun.inf").Attributes += 'Hidden'
			}
			Start-Sleep 3
		}
		Else
		{
			Log $OptimizeData.PostOptimizedImageHealthCorrupted -Type Error
			Stop-Optimize
		}

		If ($DynamicParams.BootImage)
		{
			Try
			{
				Invoke-Cleanup Boot
				$DismountBootParams = @{
					Path             = $BootMount
					Save             = $true
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.SavingDismountingImage -f $BootInfo.Name)
				[Void](Dismount-WindowsImage @DismountBootParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedSavingDismountingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				Log ($OptimizeData.RebuildingExportingImage -f $BootInfo.Name)
				Get-WindowsImage -ImagePath $BootWim | ForEach-Object -Process {
					$ExportBootParams = @{
						SourceImagePath      = $BootWim
						SourceIndex          = $PSItem.ImageIndex
						DestinationImagePath = '{0}\boot.wim' -f $WorkFolder
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						LogLevel             = 1
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportBootParams)
				}
			}
			Catch
			{
				Log ($OptimizeData.FailedRebuildingExportingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}

		If ($DynamicParams.RecoveryImage)
		{
			Try
			{
				Invoke-Cleanup Recovery
				$DismountRecoveryParams = @{
					Path             = $RecoveryMount
					Save             = $true
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.SavingDismountingImage -f $RecoveryInfo.Name)
				[Void](Dismount-WindowsImage @DismountRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedSavingDismountingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				$ExportRecoveryParams = @{
					SourceImagePath      = $RecoveryWim
					SourceIndex          = 1
					DestinationImagePath = '{0}\winre.wim' -f $WorkFolder
					CheckIntegrity       = $true
					ScratchDirectory     = $ScratchFolder
					LogPath              = $DISMLog
					LogLevel             = 1
					ErrorAction          = 'Stop'
				}
				Log ($OptimizeData.RebuildingExportingImage -f $RecoveryInfo.Name)
				[Void](Export-WindowsImage @ExportRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedRebuildingExportingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}

		If (Get-ChildItem -Path $WorkFolder -Filter boot.wim) { Get-ChildItem -Path $WorkFolder -Filter boot.wim | Move-Item -Destination $BootWim -Force }
		If (Get-ChildItem -Path $WorkFolder -Filter winre.wim)
		{
			$WinREPath = Get-ChildItem -Path $WorkFolder -Filter winre.wim | Move-Item -Destination $WinREPath -Force -PassThru
			(Get-Item -Path $WinREPath -Force).Attributes = 0x2006
		}

		Try
		{
			Invoke-Cleanup Install
			$DismountInstallParams = @{
				Path             = $InstallMount
				Save             = $true
				CheckIntegrity   = $true
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				LogLevel         = 1
				ErrorAction      = 'Stop'
			}
			Log ($OptimizeData.SavingDismountingImage -f $InstallInfo.Name)
			[Void](Dismount-WindowsImage @DismountInstallParams)
		}
		Catch
		{
			Log ($OptimizeData.FailedSavingDismountingImage -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
			Stop-Optimize
		}

		Try
		{
			if(-not $CompressionType -or $CompressionType -eq 'Select'){
				$CompressionType = Get-CompressionType -ErrorAction Stop
			}
		}
		Catch
		{
			Do
			{
				$CompressionType = @('Solid', 'Maximum', 'Fast', 'None') | Select-Object -Property @{ Label = 'Compression'; Expression = { ($PSItem) } } | Out-GridView -Title "Select Final Image Compression." -OutputMode Single | Select-Object -ExpandProperty Compression
			}
			While ($CompressionType.Length -eq 0)
		}

		Try
		{
			Log ($OptimizeData.RebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType)
			Switch ($CompressionType)
			{
				'Solid'
				{
					$SolidImage = Compress-Solid -ErrorAction Stop
					If ($SolidImage.Exists)
					{
						$InstallWim | Purge
						If ($DynamicParams.BootImage) { $ImageFiles = @('install.esd', 'boot.wim') }
						Else { $ImageFiles = 'install.esd' }
					}
					Else
					{
						If ($DynamicParams.BootImage) { $ImageFiles = @('install.wim', 'boot.wim') }
						Else { $ImageFiles = 'install.wim' }
						Throw
					}
					Break
				}
				Default
				{
					$ExportInstallParams = @{
						SourceImagePath      = $InstallWim
						SourceIndex          = $ImageIndex
						DestinationImagePath = '{0}\install.wim' -f $WorkFolder
						CompressionType      = $CompressionType
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						LogLevel             = 1
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportInstallParams)
					If ($DynamicParams.BootImage) { $ImageFiles = @('install.wim', 'boot.wim') }
					Else { $ImageFiles = 'install.wim' }
					Break
				}
			}
		}
		Catch
		{
			Log ($OptimizeData.FailedRebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType) -Type Error -ErrorRecord $Error[0]
			Start-Sleep 3
		}
		Finally
		{
			[Void](Clear-WindowsCorruptMountPoint)
		}

		If (Get-ChildItem -Path $WorkFolder -Filter install.wim) { Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $InstallWim -Force }

		If (Get-ChildItem -Path $WorkFolder -Include InstallInfo.xml, CurrentVersion.xml -Recurse -File)
		{
			Try
			{
				$InstallInfo = Get-ImageData -Update -ErrorAction Stop
			}
			Catch
			{
				Log ($OptimizeData.FailedToUpdateImageMetadata -f (GetPath -Path $InstallWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}
		Else
		{
			Log ($OptimizeData.MissingRequiredDataFiles -f (GetPath -Path $InstallWim -Split Leaf)) -Type Error
			Start-Sleep 3
		}

		If ($ISOMedia.Exists)
		{
			Log $OptimizeData.OptimizingInstallMedia
			Optimize-InstallMedia
			Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination (GetPath -Path $ISOMedia.FullName -Child sources) -Force
			If(!(Test-Path -Path "$($ISOMedia.FullName)\Autorun.inf") -and (Test-Path -Path "$($OptimizeOffline.Assets)\setup.ico")) {
				Unblock-File -Path "$($OptimizeOffline.Assets)\setup.ico"
				Set-ItemProperty -Path "$($OptimizeOffline.Assets)\setup.ico" -Name IsReadOnly -Value $false
				Copy-Item -Path (Get-Item -Path "$($OptimizeOffline.Assets)\setup.ico") -Destination $ISOMedia.FullName
				"[Autorun]
Icon=setup.ico" | Out-File "$($ISOMedia.FullName)\Autorun.inf" -Encoding ascii
				(Get-Item -Path "$($ISOMedia.FullName)\setup.ico").Attributes += 'Hidden'
				(Get-Item -Path "$($ISOMedia.FullName)\Autorun.inf").Attributes += 'Hidden'
			}
			If ($ISO)
			{
				Try
				{
					Log ($OptimizeData.CreatingISO -f $ISO)
					$ISOFile = New-ISOMedia -BootType $ISO -ErrorAction Stop
				}
				Catch
				{
					Log ($OptimizeData.FailedCreatingISO -f $ISO) -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
		}

		Try
		{
			Log $OptimizeData.FinalizingOptimizations
			$SaveDirectoryOOFiles = Create -Path (GetPath -Path $OptimizeOffline.Directory -Child Optimize-Offline_$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))) -PassThru
			If($OutputPath.ToLower().Trim() -eq 'default'){
				$SaveDirectory = $SaveDirectoryOOFiles
			} ElseIf ($OutputPath.ToLower().Trim() -ne 'select') {
				Try{
					$OutputPath = $OutputPath -replace "{filename}", $(If ($ISOFile) { (Split-Path -Path $ISOFile -leaf) } Else { "" })
					If($OutputPath -match "\.[^\.]+$"){
						$SaveDirectory = Get-Item -Path $(Split-Path -Path $OutputPath)
					} Else {
						$SaveDirectory = Get-Item -Path $OutputPath
					}
					If(!(Test-Path -Path $SaveDirectory.FullName -PathType Container)) {
						New-Item -ItemType Directory -Force -Path $SaveDirectory.FullName
					}
					Try{
						$NewFileName = (Split-Path $OutputPath -leaf)
					} Catch { Write-Debug $_.Exception.Message }
				} Catch {
					$SaveDirectory = $SaveDirectoryOOFiles
				}
			}
			If ($ISOFile) {
				Move-Item -Path $ISOFile -Destination $SaveDirectory.FullName -Force
				$MovedItem = Get-ChildItem -Path $SaveDirectory.FullName -Filter (Split-Path -Path $ISOFile -leaf)
				If ($FlashToUSB.ToLower().Trim() -ne "off" -and $USBDrive) {
					Log "Creating bootable usb."
					Try {
						Write-USB -USBDrive $USBDrive -Legacy:$(($FlashToUSB.ToLower().Trim() -eq "legacy")) -Source $ISOMedia.FullName -Label $InstallInfo.Name
						Log "Successfully created bootable usb."
					} Catch {
						Log "Failed creating bootable USB, see the error log for details" -Type Error -ErrorRecord $Error[0]
					}
				}
			} Else {
				If ($ISOMedia.Exists) {
					Move-Item -Path $ISOMedia.FullName -Destination $SaveDirectory.FullName -Force
				} Else {
					Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination $SaveDirectory.FullName -Force
				}
			}
			Try{
				If ($NewFileName -and $MovedItem -and ([IO.FileInfo]$NewFileName).Extension -eq $MovedItem.Extension){
					If($SaveDirectory.FullName -and (Test-Path -Path $($SaveDirectory.FullName+$NewFileName) -PathType Leaf)){
						Remove-Item $($SaveDirectory.FullName+$NewFileName)
					}
					Rename-Item -Path $MovedItem.FullName -NewName $NewFileName
				}
			} Catch {
				Log "Failed renaming file" -Type Error -ErrorRecord $Error[0]
			}
		}
		Finally
		{
			$OptimizeTimer.Stop()
			Log ($OptimizeData.OptimizationsCompleted -f $OptimizeOffline.BaseName, [Math]::Round($OptimizeTimer.Elapsed.TotalMinutes, 0).ToString(), ($Global:Error.Count + $OptimizeErrors.Count)) -Finalized
			If ($Global:Error.Count -gt 0 -or $OptimizeErrors.Count -gt 0) { Export-ErrorLog }
			If (Test-Path -Path (GetPath -Path $SaveDirectoryOOFiles.FullName -Child OptimizeLogs.zip)){
				Remove-Item -Path (GetPath -Path $SaveDirectoryOOFiles.FullName -Child OptimizeLogs.zip)
			}
			[Void](Get-ChildItem -Path $LogFolder -Include *.log -Exclude DISM.log -Recurse | Compress-Archive -DestinationPath (GetPath -Path $SaveDirectoryOOFiles.FullName -Child OptimizeLogs.zip) -CompressionLevel Fastest)
			If (Test-Path -Path (GetPath -Path $SaveDirectoryOOFiles.FullName -Child WimFileInfo.xml)){
				Remove-Item -Path (GetPath -Path $SaveDirectoryOOFiles.FullName -Child WimFileInfo.xml)
			}
			($InstallInfo | Out-String).Trim() | Out-File -FilePath (GetPath -Path $SaveDirectoryOOFiles.FullName -Child WimFileInfo.xml) -Encoding UTF8
			@($TempDirectory, (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log'), (GetPath -Path $Env:SystemRoot -Child 'Logs\CBS\CBS.log')) | Purge -ErrorAction Ignore
		}
		#endregion Image Finalization
	}
	End
	{
		#region Post-Processing Block
		((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $LocalScope.Variables).InputObject).ForEach{ Remove-Variable -Name $PSItem -ErrorAction Ignore }
		$ErrorActionPreference = $LocalScope.ErrorActionPreference
		$Global:ProgressPreference = $LocalScope.ProgressPreference
		If ($PSVersionTable.PSVersion.Major -eq 7) { $PSStyle.OutputRendering = 'Ansi' }
		$Global:Error.Clear()
		$Global:InstallInfo = $null
		Log "Clearing temp directory..."
		Start-Sleep 3
		Remove-Item -Recurse -Force -ErrorAction Ignore $TempDirectory
		If($ShutDownOnComplete){
			$continue = $true
			for ($i = 1; $i -le 100; $i++ )
			{
				Write-Progress -Activity "Press Spacebar to cancel shutdown" -Status "Shutting down ..." -PercentComplete $i
				Start-Sleep -Milliseconds 100
				if ([console]::KeyAvailable)
				{
					$keypress = [System.Console]::ReadKey()
					switch ($keypress.key)
					{
						Spacebar { $continue = $false }
					}
				}
				if ($continue -eq $false) {
					break
				}
			}
			Stop-Computer -ComputerName localhost
		}
		#endregion Post-Processing Block
	}
}