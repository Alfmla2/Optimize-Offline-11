Function Get-CapabilityPackages {
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

    # Fork (24H2): capabilities that are permanent or required for servicing.
    # Attempting to remove any of these from a 26100 image returns 0x800f0825
    # ("package is permanent or not applicable") and, if not caught, aborts the
    # whole run. We filter them out of the selectable list up-front instead of
    # relying solely on the per-item Try/Catch in Optimize-Offline.psm1.
    $PermanentCapabilities = @(
        'Language.Basic*'
        'MathRecognizer*'
        'Microsoft.Windows.Sense.Client*'   # Enterprise-only, permanent on 24H2
    )

    Try {
        $AllCaps = Get-WindowsCapability -Path $Path `
            -ScratchDirectory $ScratchDirectory -LogPath $LogPath -LogLevel 1 `
            -ErrorAction Stop
    }
    Catch {
        Write-Warning ('Get-CapabilityPackages: failed to enumerate capabilities: {0}' -f $_.Exception.Message)
        return @()
    }

    $WindowsCapabilities = $AllCaps |
        Where-Object {
            $PSItem.State -eq 'Installed' -and
            ($PermanentCapabilities | Where-Object { $PSItem.Name -like $_ }).Count -eq 0
        } |
        Select-Object -Property Name, State |
        Sort-Object -Property Name

    return $WindowsCapabilities
}