Function Get-AppxPackages {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    Param (
        [Parameter(Mandatory = $true,
            HelpMessage = 'full path to the root directory of the offline Windows image that you will service.')]
        [String]$Path,
        [Parameter(Mandatory = $false,
            HelpMessage = 'Specifies a temporary directory that will be used when extracting files for use during servicing.')]
        [String]$ScratchDirectory,
        [Parameter(Mandatory = $false,
            HelpMessage = 'the full path and file name to log to.')]
        [String]$LogPath
    )

    # Server Core has no provisioned Store apps. Return an empty array (not @{}),
    # because downstream code does .Count / .Where / ForEach-Object on the result.
    if ($Global:InstallInfo -and
        $Global:InstallInfo.InstallationType -and
        $Global:InstallInfo.InstallationType.ToLower().Contains('server core')) {
        return @()
    }

    $RawPackages = Get-AppxProvisionedPackage -Path $Path `
        -ScratchDirectory $ScratchDirectory -LogPath $LogPath -LogLevel 1

    $AppxPackages = $RawPackages | ForEach-Object -Process {
        $Display = $PSItem.DisplayName
        $Pkg     = $PSItem.PackageName

        # 24H2 (26100): many first-party apps are MicrosoftWindows.Client.* and
        # expose DisplayName as 'ms-resource:...' or empty. Derive a stable,
        # language-independent label from the package-name prefix, matching the
        # convention already used by Get-SystemPackages / SystemAppsTemplate.json.
        if ([String]::IsNullOrWhiteSpace($Display) -or $Display -like 'ms-resource:*') {
            $Display = if ($Pkg -match '_') { $Pkg.Split('_')[0] } else { $Pkg }
        }

        # Legacy Cortana rename — kept so existing user lists continue to match.
        if ($Display -eq 'Microsoft.549981C3F5F10') { $Display = 'CortanaApp.View.App' }

        [PSCustomObject]@{
            PackageName = [String]$Pkg
            DisplayName = [String]$Display
        }
    } | Sort-Object -Property DisplayName, PackageName

    return $AppxPackages
}