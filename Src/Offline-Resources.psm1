Using namespace System.Collections.Generic
#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
	===========================================================================
	Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2023 v5.8.218
	Created on:   	11/20/2019 11:53 AM
	Created by:   	BenTheGreat
	Filename:     	Offline-Resources.psm1
	Last updated:	02/16/2023
	-------------------------------------------------------------------------
	Module Name: Offline-Resources
	===========================================================================
#>

#region Set Local Variables
$ResourcesRoot = $PSScriptRoot
$ModuleRoot = Split-Path -Path $ResourcesRoot
#endregion Set Local Variables

#region Import Resource Functions
$PublicFunctions = @(Get-ChildItem -Path (Join-Path -Path $ResourcesRoot -ChildPath Public) -Filter *.ps1 -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path (Join-Path -Path $ResourcesRoot -ChildPath Private) -Filter *.ps1 -ErrorAction SilentlyContinue)
ForEach ($Function In @($PublicFunctions + $PrivateFunctions))
{
	Try { . $Function.FullName }
	Catch { Write-Warning ('Failed to import the required function "{0}", {1}' -f $Function.FullName, $PSItem); Break }
}
#endregion Import Resource Functions

#region Module Path Declarations
$OfflineResources = [Collections.Specialized.OrderedDictionary]::New()
$OfflineResources.Path = (Resolve-FullPath -Path $ResourcesRoot -Child Offline-Resources.psm1)
$OfflineResources.Name = (Resolve-FullPath -Path $OfflineResources.Path -Split Leaf)
$OfflineResources.BaseName = ([IO.Path]::GetFileNameWithoutExtension($OfflineResources.Name))
$OfflineResources.Directory = (Resolve-FullPath -Path $OfflineResources.Path -Split Parent)

$OptimizeOffline = [Collections.Specialized.OrderedDictionary]::New()
$OptimizeOffline.Path = (Resolve-FullPath -Path $ModuleRoot -Child Optimize-Offline.psm1)
$OptimizeOffline.Name = (Resolve-FullPath $OptimizeOffline.Path -Split Leaf)
$OptimizeOffline.BaseName = ([IO.Path]::GetFileNameWithoutExtension($OptimizeOffline.Name))
$OptimizeOffline.Directory = (Resolve-FullPath -Path $OptimizeOffline.Path -Split Parent)
$OptimizeOffline.Resources = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child Src)

# Fork: resolve the host UI culture dynamically with an en-US fallback instead of
# hardcoding 'en-US'. This removes the strict image-language vs host-culture gating
# for integrations (Edge, Dedup, Set-RegistryProperties etc.) while still providing
# a deterministic fallback when the host has no localized resource folder.
$OptimizeOffline.FallbackCulture = 'en-US'
$DetectedCulture = [System.Globalization.CultureInfo]::CurrentUICulture.Name
$CultureProbe = (Resolve-FullPath -Path $OptimizeOffline.Resources -Child "Public\$DetectedCulture\Set-RegistryProperties.strings.psd1")
if (-not (Test-Path -LiteralPath $CultureProbe)) {
    $DetectedCulture = $OptimizeOffline.FallbackCulture
}
$OptimizeOffline.Culture = $DetectedCulture

$OptimizeOffline.Content = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child Content)
$OptimizeOffline.CustomRegistry = (Resolve-FullPath -Path $OptimizeOffline.Content -Child CustomRegistry.reg)
$OptimizeOffline.LocalizedData = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child $OptimizeOffline.Culture)
$OptimizeOffline.LocalizedDataFallback = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child $OptimizeOffline.FallbackCulture)
$OptimizeOffline.Additional = (Resolve-FullPath -Path $OptimizeOffline.Content -Child Additional)
$OptimizeOffline.Assets = (Resolve-FullPath -Path $OptimizeOffline.Content -Child Assets)
$OptimizeOffline.Packages = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child Packages)
$OptimizeOffline.LocalizedDataStrings = (Resolve-FullPath -Path $OptimizeOffline.LocalizedData -Child Optimize-Offline.strings.psd1)
$OptimizeOffline.ConfigurationJSON = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child Configuration.json)
$OptimizeOffline.ManifestDataFile = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child Optimize-Offline.psd1)
$OptimizeOffline.CustomAppAssociations = (Resolve-FullPath -Path $OptimizeOffline.Content -Child CustomAppAssociations.xml)
$OptimizeOffline.DevMode = (Resolve-FullPath -Path $OptimizeOffline.Packages -Child DeveloperMode)
$OptimizeOffline.WindowsStore = (Resolve-FullPath -Path $OptimizeOffline.Packages -Child WindowsStore)
$OptimizeOffline.MicrosoftEdge = (Resolve-FullPath -Path $OptimizeOffline.Packages -Child MicrosoftEdge)
$OptimizeOffline.Dedup = (Resolve-FullPath -Path $OptimizeOffline.Packages -Child Deduplication)
# Win32Calc and DaRT paths removed — those integrations are Win10-only and were dropped in the 24H2 fork.
$OptimizeOffline.Setup = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child Setup)
$OptimizeOffline.DisableDefender = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child DisableDefender)
$OptimizeOffline.Wallpaper = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child Wallpaper)
$OptimizeOffline.SystemLogo = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child SystemLogo)
$OptimizeOffline.LockScreen = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child LockScreen)
$OptimizeOffline.RegistryTemplates = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child RegistryTemplates)
$OptimizeOffline.LayoutModification = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child LayoutModification)
$OptimizeOffline.Unattend = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child Unattend)
$OptimizeOffline.Drivers = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child Drivers)
$OptimizeOffline.InstallDrivers = (Resolve-FullPath -Path $OptimizeOffline.Drivers -Child Install)
$OptimizeOffline.BootDrivers = (Resolve-FullPath -Path $OptimizeOffline.Drivers -Child Boot)
$OptimizeOffline.RecoveryDrivers = (Resolve-FullPath -Path $OptimizeOffline.Drivers -Child Recovery)
$OptimizeOffline.SelectiveRegistry = (Resolve-FullPath -Path $OptimizeOffline.Additional -Child SelectiveRegistry)
#endregion Module Path Declarations

#region List paths
$OptimizeOffline.Lists = @{}
$OptimizeOffline.Lists.Path = (Resolve-FullPath -Path $OptimizeOffline.Content -Child Lists)

$OptimizeOffline.Lists.WindowsAppsPath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child WindowsApps)
$OptimizeOffline.Lists.WindowsAppsList = (Resolve-FullPath -Path $OptimizeOffline.Lists.WindowsAppsPath -Child WindowsAppsList.json)
$OptimizeOffline.Lists.WindowsAppsTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.WindowsAppsPath -Child WindowsAppsTemplate.json)

$OptimizeOffline.Lists.SystemAppsPath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child SystemApps)
$OptimizeOffline.Lists.SystemAppsList = (Resolve-FullPath -Path $OptimizeOffline.Lists.SystemAppsPath -Child SystemAppsList.json)
$OptimizeOffline.Lists.SystemAppsTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.SystemAppsPath -Child SystemAppsTemplate.json)

$OptimizeOffline.Lists.CapabilitiesPath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child Capabilities)
$OptimizeOffline.Lists.CapabilitiesList = (Resolve-FullPath -Path $OptimizeOffline.Lists.CapabilitiesPath -Child CapabilitiesList.json)
$OptimizeOffline.Lists.CapabilitiesTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.CapabilitiesPath -Child CapabilitiesTemplate.json)

$OptimizeOffline.Lists.PackagesPath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child Packages)
$OptimizeOffline.Lists.PackagesList = (Resolve-FullPath -Path $OptimizeOffline.Lists.PackagesPath -Child PackagesList.json)
$OptimizeOffline.Lists.PackagesTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.PackagesPath -Child PackagesTemplate.json)

$OptimizeOffline.Lists.FeaturesToEnablePath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child FeaturesToEnable)
$OptimizeOffline.Lists.FeaturesToEnableList = (Resolve-FullPath -Path $OptimizeOffline.Lists.FeaturesToEnablePath -Child FeaturesToEnableList.json)
$OptimizeOffline.Lists.FeaturesToEnableTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.FeaturesToEnablePath -Child FeaturesToEnableTemplate.json)

$OptimizeOffline.Lists.FeaturesToDisablePath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child FeaturesToDisable)
$OptimizeOffline.Lists.FeaturesToDisableList = (Resolve-FullPath -Path $OptimizeOffline.Lists.FeaturesToDisablePath -Child FeaturesToDisableList.json)
$OptimizeOffline.Lists.FeaturesToDisableTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.FeaturesToDisablePath -Child FeaturesToDisableTemplate.json)

$OptimizeOffline.Lists.ServicesPath = (Resolve-FullPath -Path $OptimizeOffline.Lists.Path -Child Services)
$OptimizeOffline.Lists.ServicesList = (Resolve-FullPath -Path $OptimizeOffline.Lists.ServicesPath -Child ServicesList.json)
$OptimizeOffline.Lists.ServicesAdvanced = (Resolve-FullPath -Path $OptimizeOffline.Lists.ServicesPath -Child ServicesAdvanced.json)
$OptimizeOffline.Lists.ServicesTemplate = (Resolve-FullPath -Path $OptimizeOffline.Lists.ServicesPath -Child ServicesTemplate.json)
#endregion List paths

## startregion GUI paths
$OptimizeOffline.GUI = @{
	Main = (Resolve-FullPath -Path $OptimizeOffline.Resources -Child GUI)
}
$OptimizeOffline.GUI.RemovalTemplates = @{
	Main = (Resolve-FullPath -Path $OptimizeOffline.GUI.Main -Child RemovalTemplates)
}
$OptimizeOffline.GUI.RemovalTemplates.WindowsApps = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child WindowsAppsTemplate.json)
$OptimizeOffline.GUI.RemovalTemplates.SystemApps = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child SystemAppsTemplate.json)
$OptimizeOffline.GUI.RemovalTemplates.Packages = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child PackagesTemplate.json)
$OptimizeOffline.GUI.RemovalTemplates.Capabilities = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child CapabilitiesTemplate.json)
$OptimizeOffline.GUI.RemovalTemplates.Features = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child FeaturesTemplate.json)
$OptimizeOffline.GUI.RemovalTemplates.Services = (Resolve-FullPath -Path $OptimizeOffline.GUI.RemovalTemplates.Main -Child ServicesTemplate.json)
## endregion GUI paths

#region Data Declarations
Try { $ManifestData = Import-PowerShellDataFile -Path $OptimizeOffline.ManifestDataFile -ErrorAction Stop }
Catch { Write-Warning ('Failed to import the manifest data file: "{0}"' -f (Resolve-FullPath -Path $OptimizeOffline.ManifestDataFile -Split Leaf)); Break }

# Fork: try the resolved culture first, fall back to en-US on failure.
# Prevents a missing localized .strings.psd1 from aborting module import on
# non-en-US hosts while still honouring localized UI strings when they exist.
$OptimizeData = $null
Try {
    Import-LocalizedData -BaseDirectory $OptimizeOffline.Directory -FileName Optimize-Offline.strings.psd1 -BindingVariable OptimizeData -UICulture $OptimizeOffline.Culture -ErrorAction Stop
}
Catch {
    if ($OptimizeOffline.Culture -ne $OptimizeOffline.FallbackCulture) {
        Try {
            Import-LocalizedData -BaseDirectory $OptimizeOffline.Directory -FileName Optimize-Offline.strings.psd1 -BindingVariable OptimizeData -UICulture $OptimizeOffline.FallbackCulture -ErrorAction Stop
        }
        Catch {
            Write-Warning ('Failed to import the localized data file: "{0}"' -f (Resolve-FullPath -Path $OptimizeOffline.LocalizedDataStrings -Split Leaf))
            Break
        }
    }
    else {
        Write-Warning ('Failed to import the localized data file: "{0}"' -f (Resolve-FullPath -Path $OptimizeOffline.LocalizedDataStrings -Split Leaf))
        Break
    }
}
#endregion Data Declarations

#region translations
$OptimizeOffline.ServicesStartLabels = @(
	$OptimizeData.ServiceStartBoot,
	$OptimizeData.ServiceStartSystem,
	$OptimizeData.ServiceStartAutomatic,
	$OptimizeData.ServiceStartManual,
	$OptimizeData.ServiceStartDisabled
)
#endregion translations

#region Variable Declarations
$LocalScope = [PSCustomObject]::New()
$DynamicParams = @{}
$ConfigParams = [Collections.Specialized.OrderedDictionary]::New()
$OptimizeErrors = [List[Object]]::New()
$TempDirectory = (Resolve-FullPath -Path $OptimizeOffline.Directory -Child OfflineTemp_$(Get-Random))
$LogFolder = (Resolve-FullPath -Path $TempDirectory -Child LogOffline)
$WorkFolder = (Resolve-FullPath -Path $TempDirectory -Child WorkOffline)
$ScratchFolder = (Resolve-FullPath -Path $TempDirectory -Child ScratchOffline)
$ImageFolder = (Resolve-FullPath -Path $TempDirectory -Child ImageOffline)
$InstallMount = (Resolve-FullPath -Path $TempDirectory -Child InstallMountOffline)
$BootMount = (Resolve-FullPath -Path $TempDirectory -Child BootMountOffline)
$RecoveryMount = (Resolve-FullPath -Path $TempDirectory -Child RecoveryMountOffline)
$ModuleLog = (Resolve-FullPath -Path $LogFolder -Child Optimize-Offline.log)
$ErrorLog = (Resolve-FullPath -Path $LogFolder -Child OptimizeErrors.log)
$RegistryLog = (Resolve-FullPath -Path $LogFolder -Child RegistrySettings.log)
$DISMLog = (Resolve-FullPath -Path $LogFolder -Child DISM.log)
$OSCDIMG = If (Get-DeploymentTool -OSCDIMG) {
	Resolve-FullPath -Path $(Get-DeploymentTool -OSCDIMG) -Child oscdimg.exe
} Elseif (Test-Path -Path $(Resolve-FullPath -Path $OptimizeOffline.Directory -Child oscdimg.exe)) {
	Resolve-FullPath -Path $OptimizeOffline.Directory -Child oscdimg.exe
} Else {
	$null
}
$DISM = If (Get-DISMPath) { Resolve-FullPath -Path $(Get-DISMPath) -Child dism.exe } Else { Resolve-FullPath -Path $Env:SystemRoot -Child 'System32\dism.exe' }
$REG = (Resolve-FullPath -Path $Env:SystemRoot -Child 'System32\reg.exe')
$REGEDIT = (Resolve-FullPath -Path $Env:SystemRoot -Child regedit.exe)
$EXPAND = (Resolve-FullPath -Path $Env:SystemRoot -Child 'System32\expand.exe')
$AllowedRemovalOptions = @('All', 'Select', 'List', 'Whitelist', 'BlackList', 'Advanced')
#endregion Variable Declarations

#region Resource Alias Creation
New-Alias -Name Create -Value New-Container
New-Alias -Name Purge -Value Remove-Container
New-Alias -Name StartExe -Value Start-Executable
New-Alias -Name Log -Value Write-Log
New-Alias -Name RegKey -Value Set-KeyProperty
New-Alias -Name RegHives -Value Get-OfflineHives
New-Alias -Name GetPath -Value Resolve-FullPath
#endregion Resource Alias Creation

# Fork: discover EVERY function defined in each Public .ps1, not just the file
# basename. Get-OfflineHives.ps1 (for example) also defines
# Get-OfflineCurrentControlSet, which the previous export silently dropped.
$PublicFunctionNames = [System.Collections.Generic.List[string]]::new()
ForEach ($FunctionFile In $PublicFunctions)
{
    $Tokens      = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $FunctionFile.FullName, [ref]$Tokens, [ref]$ParseErrors)
    $Ast.FindAll(
        { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ) | ForEach-Object {
        If (-not $PublicFunctionNames.Contains($_.Name))
        {
            [void]$PublicFunctionNames.Add($_.Name)
        }
    }
}

$ExportResourceParams = @{
    Function = $PublicFunctionNames.ToArray()
    Variable = 'OptimizeOffline', 'ManifestData', 'OptimizeData', 'LocalScope', 'DynamicParams', 'ConfigParams', 'OptimizeErrors', 'TempDirectory', 'LogFolder', 'WorkFolder', 'ScratchFolder', 'ImageFolder', 'InstallMount', 'BootMount', 'RecoveryMount', 'ModuleLog', 'ErrorLog', 'RegistryLog', 'DISMLog', 'DISM', 'OSCDIMG', 'REG', 'REGEDIT', 'EXPAND', 'AllowedRemovalOptions'
    Alias    = '*'
}
Export-ModuleMember @ExportResourceParams
