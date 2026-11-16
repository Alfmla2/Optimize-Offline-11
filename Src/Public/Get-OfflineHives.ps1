Function Get-OfflineCurrentControlSet
{
    <#
    .SYNOPSIS
        Returns the active control-set key name (e.g. 'ControlSet001') of the
        currently mounted offline SYSTEM hive.
    .DESCRIPTION
        Reads HKLM:\WIM_HKLM_SYSTEM\Select\Current and formats it as
        ControlSet<NNN>. Requires RegHives -Load to have run already; otherwise
        falls back to ControlSet001.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param(
        [Parameter(Mandatory = $false)]
        [String]$SystemHiveMount = 'HKLM:\WIM_HKLM_SYSTEM'
    )

    $SelectPath = Join-Path -Path $SystemHiveMount -ChildPath 'Select'
    if (Test-Path -LiteralPath $SelectPath) {
        $CurrentValue = (Get-ItemProperty -Path $SelectPath -Name 'Current' -ErrorAction SilentlyContinue).Current
        if ($null -ne $CurrentValue) {
            return ('ControlSet{0:D3}' -f [int]$CurrentValue)
        }
    }
    return 'ControlSet001'
}
Function Get-OfflineHives
{
    [CmdletBinding(DefaultParameterSetName = 'Load')]
    Param
    (
        [Parameter(ParameterSetName = 'Load')]
        [Switch]$Load,
        [Parameter(ParameterSetName = 'Unload')]
        [Switch]$Unload
    )

    Begin
    {
        $Hive = [Ordered]@{
            SOFTWARE = (GetPath -Path $InstallMount -Child 'Windows\System32\Config\SOFTWARE')
            SYSTEM   = (GetPath -Path $InstallMount -Child 'Windows\System32\Config\SYSTEM')
            DEFAULT  = (GetPath -Path $InstallMount -Child 'Windows\System32\Config\DEFAULT')
            NTUSER   = (GetPath -Path $InstallMount -Child 'Users\Default\NTUSER.DAT')
        }
        $HiveMountPoint = [Ordered]@{
            SOFTWARE      = 'WIM_HKLM_SOFTWARE'
            SYSTEM        = 'WIM_HKLM_SYSTEM'
            DEFAULT       = 'WIM_HKU_DEFAULT'
            NTUSER        = 'WIM_HKCU'
            SYSTEM_BOOT   = 'BOOT_HKLM_SYSTEM'
        }

        # Fork (24H2): only probe BootMount if it is actually set — otherwise
        # GetPath -Path $null resolves relative to CWD and can yield false positives.
        if ($BootMount -and (Test-Path -LiteralPath $BootMount)) {
            $BootSystemHive = GetPath -Path $BootMount -Child 'Windows\System32\Config\SYSTEM'
            if (Test-Path -LiteralPath $BootSystemHive) {
                $Hive.SYSTEM_BOOT = $BootSystemHive
            }
        }

        $HKLM = 0x80000002
        'SeBackupPrivilege', 'SeRestorePrivilege' | Grant-Privilege
    }
    Process
    {
        Switch ($PSCmdlet.ParameterSetName)
        {
            'Load'
            {
                $RegLoad = Import-Win32API -Load

                # Fork (24H2): iterate per-hive instead of "all-or-nothing".
                # Previously, a partial mount (e.g. an interrupted prior run) left
                # missing hives unloaded while skipping the load entirely because
                # !@($true,$true) is $false.
                ForEach ($Key In $Hive.Keys) {
                    $MountPoint = $HiveMountPoint[$Key]
                    $Source     = $Hive[$Key]

                    if (-not $MountPoint -or -not $Source) { continue }
                    if (-not (Test-Path -LiteralPath $Source)) {
                        # Source file missing (e.g. DEFAULT on some LTSC SKUs) — skip.
                        continue
                    }
                    if (Test-Path -LiteralPath ('HKLM:\{0}' -f $MountPoint)) {
                        # Already mounted — leave as-is.
                        continue
                    }

                    $Result = $RegLoad::RegLoadKey($HKLM, $MountPoint, $Source)
                    if ($Result -ne 0 -and $null -ne $Result) {
                        Log ('RegLoadKey failed for {0} ({1}); code {2}' -f $MountPoint, $Source, $Result) -Type Error
                    }
                }
                Break
            }
            'Unload'
            {
                # Determine which mount points are actually loaded, then retry
                # unloading only those. This avoids issuing useless RegUnLoadKey
                # calls against hives that were never mounted.
                $LoadedMountPoints = @(
                    $HiveMountPoint.Values | Where-Object {
                        Test-Path -LiteralPath ('HKLM:\{0}' -f $_)
                    }
                )

                if ($LoadedMountPoints.Count -gt 0) {
                    $RegUnload = Import-Win32API -Unload
                    [GC]::Collect()
                    [GC]::WaitForPendingFinalizers()

                    $Retries = $LoadedMountPoints.Count + 2
                    while ($Retries -gt 0 -and $LoadedMountPoints.Count -gt 0) {
                        $LoadedMountPoints | ForEach-Object {
                            [void]$RegUnload::RegUnLoadKey($HKLM, $_)
                        }
                        Start-Sleep -Seconds 1

                        $LoadedMountPoints = @(
                            $HiveMountPoint.Values | Where-Object {
                                Test-Path -LiteralPath ('HKLM:\{0}' -f $_)
                            }
                        )
                        if ($LoadedMountPoints.Count -gt 0) {
                            Start-Sleep -Seconds 3
                        }
                        $Retries--
                    }

                    if ($LoadedMountPoints.Count -gt 0) {
                        Log ('Failed to unload registry hives: {0}' -f ($LoadedMountPoints -join ', ')) -Type Error
                    }
                }
                Break
            }
        }
    }
    End
    {
        'SeBackupPrivilege', 'SeRestorePrivilege' | Grant-Privilege -Disable
    }
}