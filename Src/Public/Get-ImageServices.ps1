Function Get-ImageServices {
    [CmdletBinding()]
    [OutputType([System.Object[]], [System.Collections.ArrayList])]
    Param()

    $ServicesStartLabels = @(
        'Boot',
        'System',
        'Automatic',
        'Manual',
        'Disabled'
    )

    # Fork (24H2): services that must never be offered for disabling.
    # Disabling any of these bricks the image or breaks DISM / servicing / login.
    # The caller (Optimize-Offline.psm1 -Services) already runs RegHives -Load,
    # so this function does NOT load/unload hives itself.
    $PermanentServices = @(
        'RpcSs','RpcEptMapper','DcomLaunch','LSM','Power','PlugPlay','SamSs',
        'BrokerInfrastructure','CoreMessagingRegistrar','Winmgmt','ProfSvc',
        'Schedule','UserManager','EventLog','gpsvc','DsmSvc',
        'TrustedInstaller','CryptSvc','StateRepository','SystemEventsBroker',
        'Wcmsvc','Themes'
    )
    # Fork (24H2): resolve the actual ControlSet. Use the caller's $CCS if it exists,
    # otherwise resolve it locally, then fall back to ControlSet001.
    $ResolvedCCS = if ($CCS) {
        $CCS
    } elseif (Get-Command -Name Get-OfflineCurrentControlSet -ErrorAction SilentlyContinue) {
        Get-OfflineCurrentControlSet
    } else {
        'ControlSet001'
    }

    # Используем двойные кавычки для интерполяции переменной $ResolvedCCS
    $RegPath = "HKLM:\WIM_HKLM_SYSTEM\$ResolvedCCS\Services"
    $Services = [System.Collections.ArrayList]@()

    Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ValueCount -gt 0 -and
            $_.PSChildName -notin $PermanentServices
        } |
        ForEach-Object -Process {
            $Name = $_.PSChildName
            $FolderKeys = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue

            if ($null -eq $FolderKeys.Start) { return }

            # 24H2: Start is sometimes stored as string; cast so -gt / index work.
            $Start = [int]$FolderKeys.Start

            # Same filters as the original: exclude Boot(0), System(1), Disabled(4),
            # and services owned by a driver (Owners value present).
            if ($Start -le 1 -or $Start -eq 4 -or $null -ne $FolderKeys.Owners) { return }

            # Description: prefer the localized DisplayName exposed by the host SCM
            # when the service exists on the host (most do); fall back to the raw
            # registry DisplayName value (a resource ref — still better than blank).
            $ServiceDetails = Get-Service -Name $Name -ErrorAction SilentlyContinue
            $Description = if ($ServiceDetails -and $ServiceDetails.DisplayName) {
                $ServiceDetails.DisplayName
            } elseif ($FolderKeys.DisplayName) {
                [String]$FolderKeys.DisplayName
            } else {
                ''
            }

            # 24H2 safety: bound-check the label index instead of trusting the array.
            $Label = if ($Start -ge 0 -and $Start -lt $ServicesStartLabels.Count) {
                $ServicesStartLabels[$Start]
            } else { 'Unknown' }

            [Void]$Services.Add([PSCustomObject]@{
                name        = [String]$Name
                description = [String]$Description
                start       = $Start
                startLabel  = $Label
            })
        }

    return $Services
}