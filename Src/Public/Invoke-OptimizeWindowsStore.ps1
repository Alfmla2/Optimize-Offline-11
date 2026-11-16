Function Invoke-OptimizeWindowsStore
{
    <#
    .SYNOPSIS
        Minimal Windows Store integration: provisions ONLY Microsoft.WindowsStore
        with its direct runtime dependencies (VCLibs 14.00, UI.Xaml 2.x,
        NET.Native Runtime/Framework). No Purchase App, no Xbox Identity, no WinGet.
    .DESCRIPTION
        Version-agnostic (wildcards match any build). Non-fatal: failures are logged
        and skipped (do not abort the whole run).

        Required files in $OptimizeOffline.WindowsStore:
          - WinStore2_*.msix                (or Microsoft.WindowsStore_*.msixbundle)
          - Microsoft.VCLibs.140.00_*.Appx
          - Microsoft.UI.Xaml.2.8_*.Appx    (falls back to any 2.x if 2.8 is absent)
          - Microsoft.NET.Native.Runtime.2.2_*.Appx
          - Microsoft.NET.Native.Framework.2.2_*.Appx
        Optional:
          - Microsoft.WindowsStore*.xml     (license; if absent, provisions with -SkipLicense)
    .NOTES
        Always sets $DynamicParams.WindowsStore and $DynamicParams.DisableDeliveryOptimization —
        Set-RegistryProperties reads them downstream even when -WindowsStore is not requested.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [String]$InstallMount,
        [Parameter(Mandatory)] [String]$ScratchFolder,
        [Parameter(Mandatory)] [String]$DISMLog,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$OptimizeOffline,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$DynamicParams,
        [Parameter()]          [Object[]]$AppxPackages,
        [Parameter()]          [Switch]$WindowsStore
    )

    # Always set flags (Set-RegistryProperties reads them later, even without -WindowsStore).
    $StoreInImage     = [bool]($AppxPackages | Where-Object -Property DisplayName -EQ 'Microsoft.WindowsStore')
    $InstallerInImage = @($AppxPackages | Where-Object -Property DisplayName -EQ 'Microsoft.DesktopAppInstaller').Count -gt 0
    $DynamicParams.WindowsStore = $StoreInImage
    $DynamicParams.DisableDeliveryOptimization = (-not $StoreInImage -and -not $InstallerInImage)

    If (-not $WindowsStore) { return }
    If ($StoreInImage) { return }

    # Discover Store package by wildcard — supports WinStore2_*.msix, Microsoft.WindowsStore_*.msixbundle, etc.
    $StoreBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in '.msix', '.msixbundle' -and
            $_.Name -match 'Store' -and
            $_.Name -notmatch 'Purchase|DesktopApp|XboxIdentity'
        } |
        Sort-Object -Property Length -Descending |
        Select-Object -First 1

    If (-not $StoreBundle) {
        Write-Log ("Windows Store package not found in {0} — skipping." -f $OptimizeOffline.WindowsStore) -Type Warning
        return
    }

    # Optional license — Store can self-activate online at first MSA sign-in without it.
    $StoreLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.WindowsStore*.xml' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName

    # Dependencies — newest of each (wildcard, version-agnostic).
    $DependencyVCLibs = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.VCLibs.140.00_*.appx' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    $DependencyXAML = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.UI.Xaml.2.8_*.appx' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    If (-not $DependencyXAML) {
        # Fallback: any UI.Xaml 2.x
        $DependencyXAML = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.UI.Xaml.2.*_*.appx' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    $DependencyNativeRuntime = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.NET.Native.Runtime.2.2_*.appx' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    $DependencyNativeFramework = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter 'Microsoft.NET.Native.Framework.2.2_*.appx' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName

    $DependencyPackages = [Collections.Generic.List[String]]::New()
    @($DependencyNativeFramework, $DependencyNativeRuntime, $DependencyVCLibs, $DependencyXAML) |
        Where-Object { $_ } | ForEach-Object { $DependencyPackages.Add($_) }

    Write-Log $OptimizeData.IntegratingWindowsStore

    # AllowAllTrustedApps=1 during provisioning; restore afterwards unless DeveloperMode owns the flag.
    $ToggledTrustedApps = $false
    If (-not $DynamicParams.DeveloperMode) {
        RegHives -Load
        RegKey -Path 'HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowAllTrustedApps' -Value 1 -Type DWord
        RegHives -Unload
        $ToggledTrustedApps = $true
    }

    Try
    {
        Write-Log ("Adding Store package: {0}" -f $StoreBundle.Name)
        If ($StoreLicense) {
            Write-Log ("Using Store license: {0}" -f (Split-Path -Path $StoreLicense -Leaf))
            [Void](Add-AppxProvisionedPackage -Path $InstallMount `
                -PackagePath $StoreBundle.FullName `
                -DependencyPackagePath $DependencyPackages `
                -LicensePath $StoreLicense `
                -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop)
        }
        Else {
            Write-Log "No Store license XML found — provisioning with -SkipLicense." -Type Info
            [Void](Add-AppxProvisionedPackage -Path $InstallMount `
                -PackagePath $StoreBundle.FullName `
                -DependencyPackagePath $DependencyPackages `
                -SkipLicense `
                -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop)
        }
        $DynamicParams.WindowsStore = $true
    }
    Catch
    {
        Write-Log $OptimizeData.FailedIntegratingWindowsStore -Type Error -ErrorRecord $Error[0]
        Start-Sleep 3
    }
    Finally
    {
        If ($ToggledTrustedApps) {
            RegHives -Load
            RegKey -Path 'HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowAllTrustedApps' -Value 0 -Type DWord
            RegHives -Unload
        }
    }
}