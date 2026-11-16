Function Invoke-OptimizeDeveloperMode
{
    <#
    .SYNOPSIS
        Integrates the Developer Mode feature into a mounted offline Windows image.
    .DESCRIPTION
        Adds Microsoft-OneCore-DeveloperMode-Desktop-Package CAB to the image and
        enables the two AppModelUnlock values so sideloading/development works.
        Non-fatal: failures are logged and skipped (do not abort the whole run).
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [String]$InstallMount,
        [Parameter(Mandatory)] [String]$ScratchFolder,
        [Parameter(Mandatory)] [String]$DISMLog,
        [Parameter(Mandatory)] [String]$WorkFolder,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$OptimizeOffline,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$DynamicParams
    )

    # Fork (24H2): FOD source-CAB uses ~<pubkey>~<arch>~~.cab naming (no version),
    # while installed form uses ~<arch>~~<version>.cab. Both are valid; discover by wildcard.
    $DevModeCabFile = Get-ChildItem -Path $OptimizeOffline.DevMode -Filter '*DeveloperMode-Desktop-Package*.cab' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*~$($Global:InstallInfo.Architecture)~*" } |
        Sort-Object -Property Length -Descending |
        Select-Object -First 1

    If (-not $DevModeCabFile) {
        Write-Log ("DeveloperMode CAB for {0} not found in {1} — skipping." -f $Global:InstallInfo.Architecture, $OptimizeOffline.DevMode) -Type Warning
        return
    }

    $DevModeCab    = $DevModeCabFile.FullName
    $DevModeExpand = Create -Path (GetPath -Path $WorkFolder -Child DeveloperMode) -PassThru

    Write-Log $OptimizeData.IntegratingDeveloperMode

    [Void](StartExe $EXPAND -Arguments ('"{0}" F:* "{1}"' -f $DevModeCab, $DevModeExpand.FullName))
	Write-Log ("Adding Developer Mode package: {0}" -f $DevModeCabFile.Name)
    Try
    {
        $RET = StartExe $DISM -Arguments ('/Image:"{0}" /Add-Package /PackagePath:"{1}" /ScratchDir:"{2}" /LogPath:"{3}" /LogLevel:1' -f $InstallMount, (GetPath -Path $DevModeExpand.FullName -Child update.mum), $ScratchFolder, $DISMLog) -ErrorAction Stop
        If ($RET -eq 0) { $DynamicParams.DeveloperMode = $true }
        Else            { Throw "DISM Add-Package returned exit code $RET" }
    }
    Catch
    {
        Write-Log $OptimizeData.FailedIntegratingDeveloperMode -Type Error
        Start-Sleep 3
        return
    }

    If ($DynamicParams.DeveloperMode)
    {
        RegHives -Load
        RegKey -Path 'HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowAllTrustedApps' -Value 1 -Type DWord
        RegKey -Path 'HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord
        RegHives -Unload
    }
}