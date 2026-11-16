Function Get-OtherWindowsPackages {
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

    # Fork (24H2): package name patterns that must never be offered for removal.
    # These are either servicing-stack / cumulative updates (permanent on 26100)
    # or language features already covered by the Capabilities list. Removing
    # them either fails with 0x800f0825 or breaks the image's servicing baseline.
    $ExcludedPatterns = @(
        '*20H2Enablement*'
        '*LanguageFeatures-Basic*'
        '*LanguageFeatures-TextToSpeech*'
        '*LanguageFeatures-Handwriting*'
        '*LanguageFeatures-Speech*'
        '*LanguageFeatures-OCR*'
        '*LanguagePack*'                 # language packs are handled via Capabilities
        '*ServicingStack*'
        '*SSU*'
        '*CumulativeUpdate*'
        '*KB[0-9]*'                     # LCUs / SSUs delivered as KB packages
        '*Foundation*'                  # Foundation packages are not removable
    )

    Try {
        $AllPackages = Get-WindowsPackage -Path $Path `
            -ScratchDirectory $ScratchDirectory -LogPath $LogPath -LogLevel 1 `
            -ErrorAction Stop
    }
    Catch {
        Write-Warning ('Get-OtherWindowsPackages: failed to enumerate packages: {0}' -f $_.Exception.Message)
        return @()
    }

    # 24H2: ReleaseType can also be 'Foundation'. We include only the removable
    # release types and exclude anything matching the permanent/servicing patterns.
    $WindowsPackages = $AllPackages |
        Where-Object {
            $PSItem.PackageState -eq 'Installed' -and
            $PSItem.ReleaseType -in @('OnDemandPack', 'LanguagePack', 'FeaturePack') -and
            ($ExcludedPatterns | Where-Object { $PSItem.PackageName -like $_ }).Count -eq 0
        } |
        Select-Object -Property PackageName, ReleaseType |
        Sort-Object -Property PackageName

    return $WindowsPackages
}