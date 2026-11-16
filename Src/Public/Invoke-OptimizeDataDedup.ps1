Function Invoke-OptimizeDataDedup {
    <#
    .SYNOPSIS
        Integrates Windows Server Data Deduplication into a mounted offline image.
    .DESCRIPTION
        Fork (24H2): dynamic package discovery per target language; strictly separates
        base CABs from language CABs; discovers the actual Dedup feature name before
        enabling; applies firewall rules when enabled.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [String]$InstallMount,
        [Parameter(Mandatory)] [String]$ScratchFolder,
        [Parameter(Mandatory)] [String]$DISMLog,
        [Parameter(Mandatory)] [String]$CCS,
        [Parameter(Mandatory)] [String]$DedupFolder,
        [Parameter(Mandatory)] [Hashtable]$DynamicParams,
        [Parameter(Mandatory)] [PSObject]$OptimizeData
    )

    If (-not $DynamicParams.ContainsKey('DataDeduplication')) {
        $DynamicParams.DataDeduplication = $false
    }

    If (-not (Test-Path -Path $DedupFolder -Filter Microsoft-Windows-FileServer-Core-Package*.cab) -or
        -not (Test-Path -Path $DedupFolder -Filter Microsoft-Windows-FileServer-ServerCore-Package*.cab) -or
        -not (Test-Path -Path $DedupFolder -Filter Microsoft-Windows-Dedup-Package*.cab) -or
        (Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 |
            Where-Object { $_.PackageName -like '*Windows-Dedup*' -or $_.PackageName -like '*FileServer-Core*' -or $_.PackageName -like '*FileServer-ServerCore*' }))
    {
        return
    }

    $DedupFeatureName = 'Dedup-Core'
    Try {
        Log $OptimizeData.IntegratingDataDedup

        $LanguageSuffixPattern = '-[a-z]{2}-[A-Z]{2}\.cab$'

        $DedupBaseCab = Get-ChildItem -Path $DedupFolder -Filter 'Microsoft-Windows-Dedup-Package-*.cab' -File |
            Where-Object { $_.Name -notmatch $LanguageSuffixPattern } |
            Sort-Object Name -Descending | Select-Object -First 1
        $FileServerCoreCab = Get-ChildItem -Path $DedupFolder -Filter 'Microsoft-Windows-FileServer-Core-Package-*.cab' -File |
            Where-Object { $_.Name -notmatch $LanguageSuffixPattern } |
            Sort-Object Name -Descending | Select-Object -First 1
        $FileServerServerCoreCab = Get-ChildItem -Path $DedupFolder -Filter 'Microsoft-Windows-FileServer-ServerCore-Package-*.cab' -File |
            Where-Object { $_.Name -notmatch $LanguageSuffixPattern } |
            Sort-Object Name -Descending | Select-Object -First 1

        If (-not ($DedupBaseCab -and $FileServerCoreCab -and $FileServerServerCoreCab)) {
            Throw 'Missing base CABs. Required: FileServer-Core, FileServer-ServerCore, Dedup-Package (no language suffix).'
        }

        $BasePackages = @($FileServerCoreCab.FullName, $FileServerServerCoreCab.FullName, $DedupBaseCab.FullName)
        $LangCandidates = Get-ChildItem -Path $DedupFolder -Filter '*.cab' -File |
            Where-Object { $_.Name -match $LanguageSuffixPattern } |
            Select-Object -ExpandProperty FullName
        $AllDedupPackages = @($BasePackages + $LangCandidates) |
            Where-Object { $_ -and (Test-Path -Path $_) } | Select-Object -Unique

        If (-not $AllDedupPackages) { Throw "No matching Dedup packages found in '$DedupFolder'." }

        $AllDedupPackages | ForEach-Object -Process {
            Log ("Adding Dedup package: {0}" -f (Split-Path -Path $_ -Leaf))
            [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $_ -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop)
        }

        Try {
            $FeatureCatalogue = Get-WindowsOptionalFeature -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop
            $DetectedDedup = $FeatureCatalogue | Where-Object { $_.FeatureName -match 'Dedup' } | Select-Object -First 1
            If ($DetectedDedup) {
                $DedupFeatureName = $DetectedDedup.FeatureName
                Log ("Discovered Dedup feature in image: {0}" -f $DedupFeatureName)
            } Else {
                Log ("No 'Dedup*' feature found; falling back to '{0}'." -f $DedupFeatureName) -Type Warning
            }
        } Catch {
            Log ("Unable to enumerate optional features: {0}" -f $_.Exception.Message) -Type Warning
        }

        $EnableDedup = @{
            Path = $InstallMount; FeatureName = $DedupFeatureName; All = $true; LimitAccess = $true
            NoRestart = $true; ScratchDirectory = $ScratchFolder; LogPath = $DISMLog; LogLevel = 1
            ErrorAction = 'Stop'
        }
        [Void](Enable-WindowsOptionalFeature @EnableDedup)
        $DynamicParams.DataDeduplication = $true
    } Catch {
        If ($_.Exception.Message -match 'неизвестн|unknown') {
            Log ("Data Deduplication feature '{0}' is not available on this SKU." -f $DedupFeatureName) -Type Warning
        } Else {
            Log $OptimizeData.FailedIntegratingDataDedup -Type Error -ErrorRecord $Error[0]
        }
        Start-Sleep 3
    }

	If ($DynamicParams.DataDeduplication)
	{
		RegHives -Load
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-DCOM-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=135|App=%systemroot%\system32\svchost.exe|Svc=RPCSS|Name=File Server Remote Management (DCOM-In)|Desc=Inbound rule to allow DCOM traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-SMB-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|App=System|Name=File Server Remote Management (SMB-In)|Desc=Inbound rule to allow SMB traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-Winmgmt-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=RPC|App=%systemroot%\system32\svchost.exe|Svc=Winmgmt|Name=File Server Remote Management (WMI-In)|Desc=Inbound rule to allow WMI traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-DCOM-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=135|App=%systemroot%\system32\svchost.exe|Svc=RPCSS|Name=File Server Remote Management (DCOM-In)|Desc=Inbound rule to allow DCOM traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-SMB-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|App=System|Name=File Server Remote Management (SMB-In)|Desc=Inbound rule to allow SMB traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\$CCS\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-Winmgmt-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=RPC|App=%systemroot%\system32\svchost.exe|Svc=Winmgmt|Name=File Server Remote Management (WMI-In)|Desc=Inbound rule to allow WMI traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
		RegHives -Unload
	}
}