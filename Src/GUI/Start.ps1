Add-Type -AssemblyName PresentationFramework, System.Windows.Forms

$Global:Error.Clear()

$RootPath = $PSScriptRoot

$OO_Root_Path = (Get-Item -Path "$RootPath\..\..\").FullName
$OO_Lists_Path = "$($OO_Root_Path)Content\Lists\"
$ConsoleSTDOutPath = "$($OO_Root_Path)ConsoleOut.txt"
$CustomRegistryPath = "$($OO_Root_Path)\Content\CustomRegistry.reg"

$RemovalTypes = @("Blacklist", "Whitelist")
$ListTypes = @("WindowsApps", "SystemApps", "Capabilities", "Packages", "Services", "Features")
$ListTypesNoRemoval = @("Services", "Features")
$ListColumns = @{
	"WindowsApps"  = @("DisplayName", "PackageName")
	"SystemApps"   = @("DisplayName", "PackageName")   # ← PackageName добавлен
	"Capabilities" = @("Name")
	"Packages"     = @("PackageName")
	"Services"     = @("Name", "Description", "OriginalStart")
	"Features"     = @("FeatureName", "OriginalState")
}
$ListMainKey = @{
	"WindowsApps" = "DisplayName"
	"SystemApps" = "SystemApps"   # { SystemApps: [{PackageName, DisplayName}] }
	"Capabilities" = "Name"
	"Packages" = "PackageName"
	"Services" = "Services"
	"Features" = "FeatureName"
}
$ListColumnsComboBox = @{
	"Features" = @("State")
	"Services" = @("Start")
}

Function CleanVars {
	Remove-Variable -Name Configuration, ConfigurationDef -ErrorAction Ignore
	Remove-Variable -Name OO_GUI_FlashUSBDriveNumber, OO_GUI_Timer, OO_GUI_Job -ErrorAction Ignore -Scope Global
	Foreach($ListType in $ListTypes) {
		Remove-Variable -Name "$($ListType)Template" -ErrorAction Ignore -Scope Global
	}
	If (Test-Path -Path "$ConsoleSTDOutPath") {
		Remove-Item -Path "$ConsoleSTDOutPath"
	}
}

CleanVars

$Global:OO_GUI_FlashUSBDriveNumber = -1

$Global:OO_GUI_Timer = New-Object System.Windows.Forms.Timer
$Global:OO_GUI_Timer.Interval = 3000

$Global:OO_GUI_Job = $null


$Configuration_path = (Get-Item -Path "$($OO_Root_Path)Configuration.json").FullName

## Import XAML files
Get-ChildItem -Path "$RootPath\XAML" -Filter *.xaml -Recurse | ForEach-Object -Process {
	New-Variable -Name "$($_.BaseName)XAML" -Value (Get-Content -Raw -Path $_.FullName) -Scope Script
}

## Import the List templates
Function Import-Templates {
	Foreach($ListType in $ListTypes){
		If(Test-Path -Path "$RootPath\RemovalTemplates\$($ListType)Template.json") {
			$JSON = Get-Content -Raw -Path "$RootPath\RemovalTemplates\$($ListType)Template.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
		} Else {
			$JSON = @()
		}
		If(!$JSON){
			$JSON = @()
		}
		# Fork: WindowsApps имеет legacy-формат, отличный от остальных списков.
		# Optimize-Offline.psm1 пишет его через "$ItemsGUI | ConvertTo-Json", а
		# PowerShell в этом случае превращает одноэлементный массив в одиночный
		# объект {PackageName, DisplayName, Selected} вместо [{...}].
		# На LTSC провижининг-приложение ровно одно (SecHealthUI), поэтому
		# ConvertFrom-Json даёт PSCustomObject → WPF не может его отобразить.
		# Оборачиваем только для WindowsApps, все остальные списки — уже массивы.
		If ($ListType -eq 'WindowsApps' -and $null -ne $JSON -and $JSON -isnot [array]) {
			If ($JSON.PSObject.Properties['DisplayName'] -and $JSON.DisplayName -is [System.Array]) {
				# Wrapper { DisplayName: ["A","B"] } из $Items (старый путь)
				$Wrapped = @()
				Foreach ($n in $JSON.DisplayName) {
					$Wrapped += [PSCustomObject]@{
						DisplayName = [string]$n
						PackageName = ''
						Selected    = $false
					}
				}
				$JSON = $Wrapped
			}
			ElseIf ($JSON.PSObject.Properties['DisplayName']) {
				# Одиночный объект {PackageName, DisplayName, Selected} из $ItemsGUI с 1 элементом
				$JSON = @($JSON)
			}
		}
		Switch($ListType) {
			"Services"{
				$Key = $ListMainKey.$ListType
				$List_OO = $(Get-Content -Raw -Path "$OO_Lists_Path\Services\ServicesList.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).$Key
				If($List_OO){
					Foreach($Item in $JSON) {
						Foreach($ItemOO in $List_OO) {
							If ($Item.Name -eq $ItemOO -or ($ItemOO -Match "\*" -and $Item.Name -like $ItemOO)){
								$Item.Start = $Item.Starts[4]
								Break
							}
						}
					}
				}
				$List_OO = $(Get-Content -Raw -Path "$OO_Lists_Path\Services\ServicesAdvanced.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).$Key
				If($List_OO){
					Foreach($Item in $JSON) {
						Foreach($ItemOO in $List_OO) {
							If($Item.Name -eq $ItemOO.name) {
								$Item.Start = $Item.Starts[$ItemOO.start]
								Break
							}
						}
					}
				}
			}
			"Features" {
				$Key = $ListMainKey.$ListType
				$List_OO_ToDisable = $(Get-Content -Raw -Path "$OO_Lists_Path\FeaturesToDisable\FeaturesToDisableList.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).$Key
				$List_OO_ToEnable = $(Get-Content -Raw -Path "$OO_Lists_Path\FeaturesToEnable\FeaturesToEnableList.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).$Key
				If($List_OO_ToDisable){
					Foreach($Item in $JSON) {
						Foreach($ItemOO in $List_OO_ToDisable){
							If ($Item.$Key -eq $ItemOO -or ($ItemOO -Match "\*" -and $Item.$Key -like $ItemOO)){
								$Item.State = "Disabled"
							}
						}
					}
				}
				If($List_OO_ToEnable){
					Foreach($Item in $JSON) {
						Foreach($ItemOO in $List_OO_ToEnable){
							If ($Item.$Key -eq $ItemOO -or ($ItemOO -Match "\*" -and $Item.$Key -like $ItemOO)){
								$Item.State = "Enabled"
							}
						}
					}
				}
			}
			default {
				If ($Configuration.$ListType){
					$Type = $($Configuration.$ListType).Trim()
					$Type = $Type.substring(0,1).toupper()+$Type.substring(1).tolower()
					If ($RemovalTypes.IndexOf($Type) -gt -1){
						If ($ListType -eq 'SystemApps') {
							# Fork (24H2): новый формат — { SystemApps: [{PackageName, DisplayName}] }
							# Матчинг строго по PackageName (языконезависимый идентификатор).
							$RawList = Get-Content -Raw -Path "$OO_Lists_Path\SystemApps\SystemAppsList.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
							$List_OO = @()
							If ($RawList -and $RawList.SystemApps) { $List_OO = @($RawList.SystemApps) }
							If ($List_OO.Count -gt 0) {
								Foreach ($Item in $JSON) {
									Foreach ($ItemOO in $List_OO) {
										If ($Item.PackageName -and $ItemOO.PackageName -and
											($Item.PackageName -eq $ItemOO.PackageName -or
											 ($ItemOO.PackageName -match "\*" -and $Item.PackageName -like $ItemOO.PackageName))) {
											$Item.Selected = $true
											Break
										}
									}
								}
							}
						} Else {
							$Key = $ListMainKey.$ListType
							$List_OO = (Get-Content -Raw -Path "$OO_Lists_Path\$($ListType)\$($ListType)List.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).$Key
							If($List_OO){
								Foreach($Item in $JSON) {
									Foreach($ItemOO in $List_OO){
										If ($Item.$Key -eq $ItemOO -or ($ItemOO -Match "\*" -and $Item.$Key -like $ItemOO)){
											$Item.Selected = $true
										}
									}
								}
							}
						}
					}
				}
			}
		}
		Remove-Variable -Name "$($ListType)Template" -Scope Global -ErrorAction Ignore
		New-Variable -Name "$($ListType)Template" -Value $JSON -Scope Global
	}
	Write-Host ("{0}: {1} items" -f $ListType, @($JSON).Count)
}

Import-Templates

$ConfigurationDef = Get-Content -Path "$RootPath\Configuration_definition.json" -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$Configuration = Get-Content -Path $Configuration_path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

Function Save-List {
	param([string]$ListType)
	$PathList = "$($OO_Lists_Path)$($ListType)\$($ListType)List.json"
	$PathTemplate = "$RootPath\RemovalTemplates\$($ListType)Template.json"
	$Template = (Get-Variable -Name "$($ListType)Template" -ValueOnly -Scope Global)

	If(!(Test-Path -Path $PathList) -or !(Test-Path -Path $PathTemplate)){
		return
	}

	If ($ListType -eq 'SystemApps') {
		# Fork (24H2): сохраняем { SystemApps: [{PackageName, DisplayName}] }
		$SysArr = @()
		Foreach ($Item in $Template) {
			If ($Item.Selected -and $Item.PackageName) {
				$SysArr += @{ PackageName = [string]$Item.PackageName; DisplayName = [string]$Item.DisplayName }
			}
		}
		$ListJson = @{ SystemApps = $SysArr } | ConvertTo-Json -Depth 5
	} Else {
		$List = @{ }
		$Key = $ListMainKey.$ListType
		$List.$Key = @( )
		Foreach($Item in $Template){
			If($Item.Selected){
				$List.$Key += $Item.$Key
			}
		}
		$ListJson = $List | ConvertTo-Json -Depth 5
	}

	# Всегда пишем шаблон как JSON-массив, даже если внутри 1 элемент —
	# иначе на следующем запуске ConvertFrom-Json вернёт одиночный объект.
	[object[]]$Template | ConvertTo-Json -Depth 5 | Out-File -FilePath $PathTemplate -Encoding UTF8 -Force -ErrorAction Ignore
	$ListJson | Out-File -FilePath $PathList -Encoding UTF8 -Force -ErrorAction Ignore
}

Function Save-Features {
	$FeaturesToDisable = @()
	$FeaturesToEnable = @()

	Foreach($Feature in $Global:FeaturesTemplate){
		If($Feature.State -eq "Enabled" -and $Feature.OriginalState -eq "Disabled"){
			$FeaturesToEnable += $Feature.FeatureName
		}
		If($Feature.State -eq "Disabled" -and $Feature.OriginalState -eq "Enabled"){
			$FeaturesToDisable += $Feature.FeatureName
		}
	}
	$Global:FeaturesTemplate | ConvertTo-Json | Out-File -FilePath "$RootPath\RemovalTemplates\FeaturesTemplate.json" -Encoding UTF8 -Force -ErrorAction Ignore
	@{FeatureName = $FeaturesToEnable} | ConvertTo-Json | Out-File -FilePath "$($OO_Lists_Path)FeaturesToEnable\FeaturesToEnableList.json" -Encoding UTF8 -Force -ErrorAction Ignore
	@{FeatureName = $FeaturesToDisable} | ConvertTo-Json | Out-File -FilePath "$($OO_Lists_Path)FeaturesToDisable\FeaturesToDisableList.json" -Encoding UTF8 -Force -ErrorAction Ignore
}
Function Save-Services {
	$Services = @()
	Foreach($Service in $Global:ServicesTemplate){
		If($Service.OriginalStart -ne $Service.Start) {
			$Services += @{
				name = $Service.Name
				start = $Service.Starts.IndexOf($Service.Start)
				description = $Service.Description
			}
		}
	}
	$Global:ServicesTemplate | ConvertTo-Json | Out-File -FilePath "$RootPath\RemovalTemplates\ServicesTemplate.json" -Encoding UTF8 -Force -ErrorAction Ignore
	@{Services = $Services} | ConvertTo-Json | Out-File -FilePath "$($OO_Lists_Path)Services\ServicesAdvanced.json" -Encoding UTF8 -Force -ErrorAction Ignore
}

Function GenerateControlXaml {
	param ($Control)

	$XAML = $InputLayoutXAML
	$InputControl = Switch ($Control.Type) {
		"ComboBox" {
			$ComboBoxXAML
		}
		"Switch" {
			$CheckBoxXAML
		}
		default {""}
	}

	$InputControl = $InputControl.Replace("{Name}", $Control.Name)
	$InputControl = $InputControl.Replace("{Label}", $Control.Label)

	Switch ($Control.Type) {
		"ComboBox" {
			$InputControl = $InputControl.Replace("{Value}", $($Control.Values.IndexOf(($Configuration.($Control.Binding)))))
			$InputControl = $InputControl.Replace("{Items}", $($(Foreach($Value in $Control.Values){"
			<ComboBoxItem Content='$Value' />
			"}) -join "`n"))
		}
		"Switch" {
			$InputControl = $InputControl.Replace("{Value}", "{Binding Configuration.$($Control.Binding)}")
		}
	}

	$InputControl = $InputControl.Replace("{Tooltip}", $(If($Control.Description){ $Control.Description } Else {""}))

	$XAML = $XAML.Replace("{Input}", $InputControl)

	return $XAML
}

Function Set-ControlsVisibility {
	$ImageInfo = (Get-Content -Raw -Path "$RootPath\image_info.json" -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
	If(!$ImageInfo -or !$ImageInfo.Build){
		return
	}
	$ConfigurationDef.PSObject.Properties | ForEach-Object {
		Foreach($Control in $_.Value.Controls) {
			If($Control.Restrictions -and $Control.Restrictions.Count -gt 0){
				$valid = $true
				Foreach($Restriction in $Control.Restrictions) {
					If($Restriction.Build -gt 0) {
						Switch ($Restriction.Criteria) {
							"min" {
								If($ImageInfo.Build -gt 0 -and $ImageInfo.Build -lt $Restriction.Build)
								{
									$valid = $false
									break
								}
							}
							"max" {
								If($ImageInfo.Build -gt 0 -and $ImageInfo.Build -gt $Restriction.Build)
								{
									$valid = $false
									break
								}
							}
						}
					}
				}
				$ControlWPF = $Window.FindName($Control.Name)
				$ControlWPF.Visibility = $(If (!$valid) {"Collapse"} Else {"Visible"})
				Switch($Control.Type) {
					"Switch" {
						$ControlWPF.IsChecked = $false
					}
					"ComboBox" {
						$ControlWPF.SelectedIndex = 0
					}
				}
			}
		}
	}
}

Function GenerateTabLayout {
	param ([string]$Content, [string]$TabHeader, [string]$Name, [switch]$NoScroll)
	$XAML = $(If($NoScroll.IsPresent) {$TabLayoutXAML} Else {$TabScrollXAML})
	$XAML = $XAML.Replace("{TabContent}", $Content)
	$XAML = $XAML.Replace("{TabHeader}", $TabHeader)
	$XAML = $XAML.Replace("{Name}", $Name)
	return $XAML
}

Function GenerateMainConfigTab {
	$XAML = $MainConfigTabXAML
	$TabXAML = GenerateTabLayout -Content $XAML -TabHeader "General" -Name "GeneralTab"
	$Cols = @{}
	$ConfigurationDef.PSObject.Properties | ForEach-Object -Process {
		$ControlsXAML = ""
		Foreach ($Control in $_.Value.Controls) {
			$ControlXAML = GenerateControlXaml -Control $Control
			If($ControlXAML.Trim() -ne "") {
				$ControlsXAML = $ControlsXAML + $ControlXAML
			}
		}
		If($ControlsXAML -eq ""){
			$ControlsXAML = "<TextBlock Height='30' VerticalAlignment='Center' HorizontalAlignment='Center' Width='Auto'
			Text='No configuration items available' />
			"
		}
		$SectionXAML = $MainConfigGroupBoxXAML
		$SectionXAML = $SectionXAML.Replace("{Header}", $_.Value.Label)
		$SectionXAML = $SectionXAML.Replace("{Content}", $ControlsXAML)
		If(!$Cols[$_.Value.Column]){
			$Cols[$_.Value.Column] = ""
		}
		$Cols[$_.Value.Column] += $SectionXAML
	}
	$ColsXAML = ""
	foreach($i in $Cols.keys){
		$ColsXAML += "
		<StackPanel Grid.Column='$i' Margin='0' Orientation='Vertical'>
			$($Cols[$i])
		</StackPanel>
		"
	}
	$TabXAML = $TabXAML.Replace("{ColsXAML}", $ColsXAML)
	$TabXAML = $TabXAML.Replace("{Cols}", $Cols.Count)
	return $TabXAML
}

Function GenerateListTab {
	param([string]$ListType, [string]$Header)
	If(!($Configuration.$ListType)){
		return ""
	}
	$Type = $($Configuration.$ListType).Trim()
	$Type = $Type.substring(0,1).toupper()+$Type.substring(1).tolower()
	$ListTypeSelectedIndex = $($RemovalTypes.IndexOf($Type))
	If($ListTypeSelectedIndex -lt 0){
		$ListTypeSelectedIndex = 0
	}
	$TabXAML = $ListRemovalTabXAML.Replace("{ListType}", $ListType)
	$TabXAML = $TabXAML.Replace("{ListTypeSelectedIndex}", $ListTypeSelectedIndex)
	$TabXAML = $TabXAML.Replace("{Columns}", $($(Foreach($Value in $ListColumns.$ListType){"
	<GridViewColumn DisplayMemberBinding='{Binding $Value}' Header='$Value' />
	"}) -join "`n"))
	return (GenerateTabLayout -NoScroll -Content $TabXAML -TabHeader $Header  -Name "$($ListType)Tab")
}

Function GenerateListComboTab {
	param([string]$ListType, [string]$Header)
	$TabXAML = $ListRemovalComboTabXAML.Replace("{ListType}", $ListType)
	$Columns = @()
	Foreach($Column in $ListColumns.$ListType){
		$Columns += "
			<GridViewColumn DisplayMemberBinding='{Binding $Column}' Header='$Column' />
		"
	}
	Foreach($Column in $ListColumnsComboBox.$ListType){
		$Columns += "
		<GridViewColumn Header='$Column'>
			<GridViewColumn.CellTemplate>
				<DataTemplate>
					<ComboBox Width='100' SelectedItem='{Binding ElementName=$($ListType)ListView, Path=SelectedItem.$($Column), UpdateSourceTrigger=PropertyChanged}' ItemsSource='{Binding $($Column)s, Mode=TwoWay}' SelectedValue='{Binding $($Column), Mode=TwoWay}' />
				</DataTemplate>
			</GridViewColumn.CellTemplate>
		</GridViewColumn>
		"
	}
	$TabXAML = $TabXAML.Replace("{Columns}", $Columns)
	return (GenerateTabLayout -NoScroll -Content $TabXAML -TabHeader $Header  -Name "$($ListType)Tab")
}

Function GenerateOutputTab {
	$Content = $OutputTabXAML
	return (GenerateTabLayout -NoScroll -Content $Content -TabHeader "Output" -Name "OutputTab")
}


Function GenerateCustomRegistryTab {
	$Content = $CustomRegistryTabXAML
	return (GenerateTabLayout -NoScroll -Content $Content -TabHeader "Custom Registry" -Name "CustomRegistryTab")
}


$TabsXAML = "
$(GenerateMainConfigTab)
$(GenerateListTab -ListType "WindowsApps" -Header "Windows Apps")
$(GenerateListTab -ListType "SystemApps" -Header "System Apps")
$(GenerateListTab -ListType "Capabilities" -Header "Capabilities")
$(GenerateListTab -ListType "Packages" -Header "Packages")
$(GenerateListComboTab -ListType "Features" -Header "Features")
$(GenerateListComboTab -ListType "Services" -Header "Services")
$(GenerateCustomRegistryTab)
$(GenerateOutputTab)
"
$LayoutXAML = $LayoutXAML.Replace("{Tabs}", $TabsXAML)

[xml]$XAML = @"
$LayoutXAML
"@

$Reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($Reader)

If (!$Window) {
	Exit
}

$Window.Add_Closing({
	Save-All
	CleanVars
	StopOO
})

$Window.Icon = "$RootPath\setup.ico"
$BrowseSourcePathButton = $Window.FindName("Browse_SourcePath")
$BrowseOutputPathButton = $Window.FindName("Browse_OutputPath")
$ProcessButton = $Window.FindName("ProcessButton")
$CancelButton = $Window.FindName("CancelButton")
$PopulateButton = $Window.FindName("PopulateButton")
$SelectUSB = $Window.FindName("SelectUSB")
$SelectedUSB = $Window.FindName("SelectedUSB")
$FlashToUSB = $Window.FindName("FlashToUSB")
$SourcePath = $Window.FindName("SourcePath")
$OutputPath = $Window.FindName("OutputPath")
$OutputTab = $Window.FindName("OutputTab")
$Console = $Window.FindName("Console")
$CustomRegistry = $Window.FindName("CustomRegistry")
$GeneralTab = $Window.FindName("GeneralTab")
$WindowsAppsTab = $Window.FindName("WindowsAppsTab")
$SystemAppsTab = $Window.FindName("SystemAppsTab")
$CapabilitiesTab = $Window.FindName("CapabilitiesTab")
$PackagesTab = $Window.FindName("PackagesTab")
$FeaturesTab = $Window.FindName("FeaturesTab")
$ServicesTab = $Window.FindName("ServicesTab")
$CustomRegistryTab = $Window.FindName("CustomRegistryTab")

Set-ControlsVisibility

Foreach($ListType in $ListTypes) {
	New-Variable -Name "$($ListType)ListView" -Value $Window.FindName("$($ListType)ListView")
	New-Variable -Name "$($ListType)ListFilter" -Value $Window.FindName("$($ListType)ListFilter")
	New-Variable -Name "$($ListType)ListType" -Value $Window.FindName("$($ListType)ListType")
	New-Variable -Name "$($ListType)SelectAll" -Value $Window.FindName("$($ListType)SelectAll")
	New-Variable -Name "$($ListType)SelectNone" -Value $Window.FindName("$($ListType)SelectNone")
}

Function SetControlsAccess {
	param($Enabled)
	$GeneralTab.IsEnabled = $Enabled
	$WindowsAppsTab.IsEnabled = $Enabled
	$SystemAppsTab.IsEnabled = $Enabled
	$CapabilitiesTab.IsEnabled = $Enabled
	$PackagesTab.IsEnabled = $Enabled
	$FeaturesTab.IsEnabled = $Enabled
	$ServicesTab.IsEnabled = $Enabled
	$CustomRegistryTab.IsEnabled = $Enabled
	$ProcessButton.IsEnabled = $Enabled
	$CancelButton.IsEnabled = -not $Enabled
	$PopulateButton.IsEnabled = $Enabled
	$FlashToUSB.IsEnabled = $Enabled
	$SelectUSB.IsEnabled = $Enabled
	$SourcePath.IsEnabled = $Enabled
	$BrowseSourcePathButton.IsEnabled = $Enabled
	$OutputPath.IsEnabled = $Enabled
	$BrowseOutputPathButton.IsEnabled = $Enabled
}

Function Save-Configuration {
	foreach($ListType in $ListTypes){
		If($Configuration.$ListType -and $ListTypesNoRemoval.IndexOf($ListType) -ge 0){
			continue
		}
		$Control = $Window.FindName("$($ListType)ListType")
		If($Configuration.$ListType -and $Control){
			If($RemovalTypes.IndexOf($Control.SelectedItem.Content) -ge 0){
				$Configuration.$ListType = $Control.SelectedItem.Content
			} Else {
				$Configuration.$ListType = $RemovalTypes[0]
			}
		}
	}
	$Configuration.Services = "Advanced"
	$Configuration.FeaturesToEnable = "List"
	$Configuration.FeaturesToDisable = "List"
	$Configuration | ConvertTo-Json | Out-File -FilePath $Configuration_path -Encoding UTF8 -Force -ErrorAction Ignore
}

Function SetError {
	param([string]$Err)
	$OutputTab.IsSelected = $true
	WriteToConsole -Text "`nError GUI: $Err" -Append
}

Function WriteToConsole {
	param([string]$Text, [switch]$Append)

	If($Append){
		$Console.Text += $Text
	} Else {
		$Console.Text = $Text
	}

	$Console.ScrollToEnd()
}

Function Save-All {
    # Сохраняем списки с выделениями
    Foreach ($ListType in $ListTypes) {
        If ($ListTypesNoRemoval.IndexOf($ListType) -eq -1) {
            Save-List -ListType $ListType
        }
    }
    # Сохраняем фичи и службы (даже если MouseLeave не сработал)
    Save-Features
    Save-Services
    # Сохраняем основной Configuration.json
    Save-Configuration
}

Function RunOO {
	param([switch]$populateTemplates)
	$Global:populateTemplates = $populateTemplates
	Try{
		Save-All
		$OutputTab.IsSelected = $true
		SetControlsAccess -Enabled $false
		# If we are already SYSTEM/TI, skip -Verb RunAs (ShellExecute from SYSTEM can fail).
		$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
		$IsSystemOrTI = ($Identity.Name -match 'NT AUTHORITY\\(SYSTEM|LOCAL SERVICE|NETWORK SERVICE)') -or
						($Identity.Groups.Value -contains 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')

		$StartParams = @{
			FilePath     = 'powershell'
			WindowStyle  = 'Hidden'
			ArgumentList = "Set-ExecutionPolicy Bypass -Scope Process -Force; & '$($OO_Root_Path)Start-Optimize.ps1' -GUI -FlashUSBDriveNumber $Global:OO_GUI_FlashUSBDriveNumber $(If($populateTemplates) {'-populateTemplates'} Else {''}) *>> '$($ConsoleSTDOutPath)'"
			PassThru     = $true
		}
		If (-not $IsSystemOrTI) { $StartParams.Verb = 'RunAs' }

		$Global:OO_GUI_Job = Start-Process @StartParams
		$Global:OO_GUI_Timer.Start()
	} Catch {
		SetError -Err $Error[0]
		SetControlsAccess -Enabled $true
		$Global:OO_GUI_Timer.Stop()
		If(Test-Path -path "$ConsoleSTDOutPath"){
			Remove-Item -Path "$ConsoleSTDOutPath"
		}
	}
}

Function Stop-Tree {
	Param([int]$ppid)
	Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ppid } | ForEach-Object { Stop-Tree $_.ProcessId } | Stop-Process -Id $ppid
}

Function StopOO {
	If($Global:OO_GUI_Job) {
		Stop-Tree $Global:OO_GUI_Job.Id
		Stop-Process $Global:OO_GUI_Job
	}
}

$ProcessButton.Add_Click({
	RunOO
})

$CancelButton.Add_Click({
	$continue = [System.Windows.MessageBox]::Show("Are you sure you want to cancel the processing job?", "Cancel processing", 'YesNo')
	If($continue -eq 'Yes') {
		StopOO
	}
})

$PopulateButton.Add_Click({
	RunOO -populateTemplates
})

$Window.DataContext = [PSCustomObject]@{
	Configuration = [PSCustomObject]$Configuration
}

If(Test-Path -Path $Configuration.SourcePath) {
	$SourcePath.Text = $Configuration.SourcePath
	SetControlsAccess -Enabled $true
}

$OutputPath.Text = $Configuration.OutputPath
$Configuration.FlashToUSB = "Off"

$SelectedFlashToUSBIndex = @("UEFI", "Legacy").IndexOf($Configuration.FlashToUSB)
If($SelectedFlashToUSBIndex -ge 0) {
	$FlashToUSB.SelectedIndex = $SelectedFlashToUSBIndex
}

$BrowseSourcePathButton.Add_Click({
	$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
		InitialDirectory = [Environment]::GetFolderPath('Desktop')
		Filter = 'All allowed types|*.wim;*.swm;*.iso;*.esd;*.WIM;*.SWM;*.ISO;*.ESD'
		Multiselect = $false
		AddExtension = $true
		CheckPathExists = $true
	}

	$null = $FileBrowser.ShowDialog()

	If($FileBrowser.FileName -and $FileBrowser.FileName -ne $SourcePath.Text){
		$SourcePath.Text = Get-Item -Path $FileBrowser.FileName
	}
})

$BrowseOutputPathButton.Add_Click({
	$SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
	$SaveFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
	$SourceExtension = (Get-Item $SourcePath.Text).Extension
	$SaveFileDialog.Filter = "$($SourceExtension) files (*$($SourceExtension))| *$($SourceExtension)"
	If($SaveFileDialog.ShowDialog() -eq 'Ok'){
		$OutputPath.Text = $SaveFileDialog.FileName
	}
})

$SourcePath.Add_TextChanged({
	$Enabled = ("" -ne $SourcePath.Text.Trim() -and (Test-Path -Path $SourcePath.Text.Trim()))
	$Configuration.SourcePath = $SourcePath.Text.Trim()
	Save-Configuration
	SetControlsAccess -Enabled $true
	If($Enabled){
		RunOO -populateTemplates
	}
})

$OutputPath.Add_TextChanged({
	$Configuration.OutputPath = $OutputPath.Text.Trim()
	Save-Configuration
})

Foreach($ListType in $ListTypes) {

	$SaveConfiguration = [ScriptBlock]::Create((Get-Item function:Save-Configuration).Definition)
	$SaveList = [ScriptBlock]::Create((Get-Item function:Save-List).Definition)

	$ListView = Get-Variable -Name "$($ListType)ListView" -ValueOnly

	If(!$ListView){
		Continue
	}

	$ListTemplate = (Get-Variable -Name "$($ListType)Template" -ValueOnly -Scope Global)
	# WPF ItemsSource требует IEnumerable. ConvertFrom-Json на одноэлементном массиве
	# возвращает одиночный PSCustomObject — оборачиваем только его, не трогая массивы.
	If ($null -eq $ListTemplate) {
		$ListTemplate = @()
	} ElseIf ($ListTemplate -isnot [array]) {
		$ListTemplate = @($ListTemplate)
	}
	$ListView.ItemsSource = $ListTemplate

	If($ListTypesNoRemoval.IndexOf($ListType) -eq -1){
		(Get-Variable -Name "$($ListType)SelectAll" -ValueOnly).Add_Click({
			$ListView.SelectAll()
			$ListView.Focus()
		}.GetNewClosure())
		(Get-Variable -Name "$($ListType)SelectNone" -ValueOnly).Add_Click({
			$ListView.UnselectAll()
			$ListView.Focus()
		}.GetNewClosure())
		(Get-Variable -Name "$($ListType)ListType" -ValueOnly).Add_SelectionChanged({
			$SaveConfiguration.Invoke()
			$ListView.Focus()
		}.GetNewClosure());
		$ListView.Add_SelectionChanged({
			$SaveList.Invoke($ListType)
		}.GetNewClosure());
	}

	$ListFilter = Get-Variable -Name "$($ListType)ListFilter" -ValueOnly
	$ListFilter.Add_TextChanged({
		$ListTemplate = (Get-Variable -Name "$($ListType)Template" -ValueOnly -Scope Global)
		If ($null -eq $ListTemplate) { $ListTemplate = @() }
		ElseIf ($ListTemplate -isnot [array]) { $ListTemplate = @($ListTemplate) }

		If ("" -eq $ListFilter.Text) {
			$ListView.ItemsSource = $ListTemplate
			$ListFilter.Focus()
			return
		}
		$Filtered = [System.Collections.Generic.List[object]]::new()
		foreach ($Item in $ListTemplate) {
			foreach ($prop in $Item.PSObject.Properties) {
				If ($prop.Value -like "*$($ListFilter.Text)*") {
					[void]$Filtered.Add($Item)
					Break
				}
			}
		}
		$ListView.ItemsSource = $Filtered.ToArray()
		$ListFilter.Focus()
	}.GetNewClosure())
}
#region Column sorting (click header to sort)
# Fork: три проблемы решены одновременно:
#   1) Loaded срабатывает до построения визуального дерева → 0 headers.
#      Решение: доп. хук на IsVisibleChanged — срабатывает, когда вкладка стала
#      видимой и визуальное дерево уже построено.
#   2) Loaded/IsVisibleChanged срабатывают многократно → дублируются обработчики.
#      Решение: HashSet для уже обработанных заголовков.
#   3) PS 5.1 не умеет присваивать Nullable<ListSortDirection> через dynamic
#      binding ($c.SortDirection = 'Ascending' → "Cannot find property").
#      Решение: reflection через [GridViewColumn].GetProperty('SortDirection').
Foreach ($ListType in $ListTypes) {
    $CapturedListView = Get-Variable -Name "$($ListType)ListView" -ValueOnly
    If (-not $CapturedListView) { Continue }
    $CapturedListType = $ListType
    $attachedHeaders  = [System.Collections.Generic.HashSet[System.Windows.Controls.GridViewColumnHeader]]::new()

    $attachSort = {
        param($lv, $lt, $attached)

        # Обход визуального дерева — ищем GridViewColumnHeader с Role = Normal
        # (Normal=0, Floating=1, Padding=2 — Padding это пустое место справа)
        $headers = @()
        $stack = [System.Collections.Stack]::new()
        $stack.Push($lv)
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            If ($node -is [System.Windows.Controls.GridViewColumnHeader] -and
                $node.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Normal) {
                $headers += $node
            }
            $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
            For ($i = 0; $i -lt $n; $i++) {
                $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($node, $i))
            }
        }

        $newCount = 0
        Foreach ($header in $headers) {
            # Пропускаем уже обработанные — иначе клик будет вызывать N обработчиков
            If ($attached.Contains($header)) { Continue }
            [void]$attached.Add($header)
            $newCount++

            $capturedHeader = $header
            $header.Add_Click({
                param($hSender, $hArgs)

                $column = $capturedHeader.Column
                If (-not $column) { return }

                # Путь сортировки: из DisplayMemberBinding, иначе из Header
                $sortPath = $null
                If ($column.DisplayMemberBinding -is [System.Windows.Data.Binding]) {
                    $sortPath = $column.DisplayMemberBinding.Path.Path
                }
                If (-not $sortPath) { $sortPath = [string]$column.Header }
                If (-not $sortPath) { return }

                # Toggle ASC/DESC при повторном клике по тому же столбцу
                $curSort = Get-Variable -Name "SortColumn_$lt"    -ValueOnly -Scope Global -ErrorAction Ignore
                $curAsc  = Get-Variable -Name "SortAscending_$lt" -ValueOnly -Scope Global -ErrorAction Ignore
                $ascending = If ($curSort -eq $sortPath) { -not $curAsc } Else { $true }
                Set-Variable -Name "SortColumn_$lt"    -Value $sortPath  -Scope Global -Force
                Set-Variable -Name "SortAscending_$lt" -Value $ascending -Scope Global -Force

                $items = @($lv.ItemsSource)
                If ($items.Count -le 1) { return }

                $sorted = If ($ascending) {
                    $items | Sort-Object -Property $sortPath
                } Else {
                    $items | Sort-Object -Property $sortPath -Descending
                }
                $lv.ItemsSource = @($sorted)

                # Визуальная стрелка ▲/▼ через reflection — PS 5.1 dynamic
                # binding на Nullable<ListSortDirection> падает с PropertyNotFound.
                Try {
                    $sdProp = [System.Windows.Controls.GridViewColumn].GetProperty('SortDirection')
                    If ($sdProp) {
                        Foreach ($c in $lv.View.Columns) { $sdProp.SetValue($c, $null) }
                        $dir = If ($ascending) {
                            [System.ComponentModel.ListSortDirection]::Ascending
                        } Else {
                            [System.ComponentModel.ListSortDirection]::Descending
                        }
                        $sdProp.SetValue($column, $dir)
                    }
                } Catch {Write-Debug $_.Exception.Message}

                Write-Host ("[SORT] {0} -> {1} ({2})" -f $lt, $sortPath, $(If ($ascending) {'ASC'} Else {'DESC'}))
            }.GetNewClosure())
        }

        If ($newCount -gt 0) {
            Write-Host ("[SORT] '{0}': attached to {1} new header(s)" -f $lt, $newCount)
        }
    }

    # Snapshot loop variables before creating closures — иначе все closures
    # захватят последнюю итерацию (classic PS 5.1 loop closure bug).
    $lvLocal       = $CapturedListView
    $ltLocal       = $CapturedListType
    $attachedLocal = $attachedHeaders

    # Хук 1: Loaded. Часто срабатывает ДО построения дерева → найдёт 0 headers.
    $lvLocal.Add_Loaded({
        & $attachSort $lvLocal $ltLocal $attachedLocal
    }.GetNewClosure())

    # Хук 2: IsVisibleChanged. Срабатывает, когда вкладка открывается —
    # дерево уже построено, заголовки существуют.
    $lvLocal.Add_IsVisibleChanged({
        param($vs, $ve)
        If ($vs.IsVisible) { & $attachSort $lvLocal $ltLocal $attachedLocal }
    }.GetNewClosure())
}
#endregion

$TimerTick = {
	If(Test-Path -Path "$ConsoleSTDOutPath"){
		WriteToConsole -Text (Get-Content -Path "$ConsoleSTDOutPath" -Raw -Encoding utf8)
		[Windows.Input.InputEventHandler]{ $Window.UpdateLayout() }
	}
	If($null -ne $Global:OO_GUI_Job.ExitCode){
		$Global:OO_GUI_Timer.Stop()
		SetControlsAccess -Enabled $true
		If(Test-Path -Path "$ConsoleSTDOutPath"){
			Remove-Item -Path "$ConsoleSTDOutPath"
		}
		Import-Templates
		foreach($ListType in $ListTypes) {
			$ListView = (Get-Variable -Name "$($ListType)ListView" -ValueOnly)
			If ($ListView) {
				$Tpl = (Get-Variable -Name "$($ListType)Template" -ValueOnly -Scope Global)
				If ($null -eq $Tpl) { $Tpl = @() }
				ElseIf ($Tpl -isnot [array]) { $Tpl = @($Tpl) }
				$ListView.ItemsSource = $Tpl
			}
		}
		Set-ControlsVisibility
		Save-Configuration
		WriteToConsole -Text "`nFinished" -Append
	}
}
$Global:OO_GUI_Timer.Add_Tick($TimerTick)


$ConfigurationDef.PSObject.Properties | ForEach-Object {
	Foreach($Config in $_.Value.Controls) {
		$Control = $Window.FindName($Config.Name)
		If($Control){
			Switch($Config.Type) {
				"Combobox" {
					$SaveConfiguration = [ScriptBlock]::Create((Get-Item function:Save-Configuration).Definition)
					$Control.Add_SelectionChanged({
						If($Config.Values.IndexOf($args[0].SelectedItem.Content) -gt -1){
							$Configuration.($Config.Binding) = $args[0].SelectedItem.Content
						}
						$SaveConfiguration.Invoke()
					}.GetNewClosure())
				}
				"Switch" {
					$Control.Add_Checked({
						Save-Configuration
					})
					$Control.Add_UnChecked({
						Save-Configuration
					})
				}
			}
		}
	}
}

$Window.FindName("FeaturesListView").Add_MouseLeave({
	Save-Features
})
$Window.FindName("ServicesListView").Add_MouseLeave({
	Save-Services
})

$FlashToUSB.Add_SelectionChanged({
	If($Global:OO_GUI_FlashUSBDriveNumber -ge 0){
		$Configuration.FlashToUSB = $FlashToUSB.SelectedItem.Content
	} Else {
		$Configuration.FlashToUSB = "Off"
	}
	Save-Configuration
})
$SelectUSB.Add_Click({
	$SelectedUSB.IsEnabled = $false
	$SelectedUSB.Visibility = "Collapsed"
	$USBDrives = Get-Disk | Where-Object BusType -eq USB
	If($USBDrives.Count -eq 0) {
		[System.Windows.MessageBox]::Show('No USB drives found')
		return
	}
	$USBDrive = $USBDrives | Out-GridView -Title 'Select USB Drive to Format' -OutputMode Single
	If($USBDrive){
		$SelectedUSB.Content = $USBDrive.FriendlyName
		$Global:OO_GUI_FlashUSBDriveNumber = $USBDrive.Number
		$Configuration.FlashToUSB = $FlashToUSB.SelectedItem.Content
		Save-Configuration
		$SelectedUSB.IsEnabled = $true
		$SelectedUSB.Visibility = "Visible"
	}
})

If(Test-Path -Path $CustomRegistryPath){
	$CustomRegistry.Text = Get-Content -Path $CustomRegistryPath -Raw -ErrorAction Ignore
}

$CustomRegistry.Add_MouseLeave({
	If($CustomRegistry.Text.Trim() -ne "Please input custom registry tweaks here."){
		$CustomRegistry.Text.Trim() | Out-File -Path "$($OO_Root_Path)\Content\CustomRegistry.reg"
	}
});

$Window.FindName("TabControl").Add_SelectionChanged({
	$Window.UpdateLayout()
	If($WindowsAppsTab.IsSelected){
		$Window.FindName("WindowsAppsListView").Focus()
	} Elseif ($SystemAppsTab.IsSelected){
		$Window.FindName("SystemAppsListView").Focus()
	} Elseif ($CapabilitiesTab.IsSelected){
		$Window.FindName("CapabilitiesListView").Focus()
	} Elseif ($PackagesTab.IsSelected){
		$Window.FindName("PackagesListView").Focus()
	}
})

Save-Configuration

[Void]$Window.ShowDialog()

