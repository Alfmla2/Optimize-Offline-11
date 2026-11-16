Function Import-Registry
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $false)]
        [Switch]$RegistryLoaded = $false
    )

    # Fork (24H2): guard against missing path before doing any hive work.
    if (-not (Test-Path -LiteralPath $Path)) {
        if (Get-Command -Name Log -ErrorAction SilentlyContinue) {
            Log ('Import-Registry: path not found: {0}' -f $Path) -Type Error
        }
        return
    }

    $LoadedHere = $false
    if (-not $RegistryLoaded) {
        RegHives -Load
        $LoadedHere = $true
    }

    Try {
        # Fork (24H2): resolve the actual control set from the offline SYSTEM hive
        # (Select\Current) instead of hardcoding ControlSet001. Images with a
        # non-default current control set are rare but do exist; the previous
        # code silently wrote into the wrong ControlSet in that case.
        $CurrentControlSet = 'ControlSet001'
        $SelectPath = 'HKLM:\WIM_HKLM_SYSTEM\Select'
        if (Test-Path -LiteralPath $SelectPath) {
            $CurrentValue = (Get-ItemProperty -Path $SelectPath -Name 'Current' -ErrorAction SilentlyContinue).Current
            if ($null -ne $CurrentValue) {
                $CurrentControlSet = 'ControlSet{0:D3}' -f [int]$CurrentValue
            }
        }

        # Content transformer. Deliberately keeps -replace order:
        #   1) CurrentControlSet first — otherwise the generic SYSTEM rule eats it
        #      and the offline hive never sees ControlSet001 (bug in the original).
        #   2) SYSTEM rule for everything else (explicit ControlSet00N, Setup, etc.).
        #   3) .DEFAULT uses an escaped dot so HKEY_USERS\XDEFAULT is not matched.
        #   4) HKEY_CLASSES_ROOT maps onto the SOFTWARE\Classes subtree.
        $TransformContent = {
            param(
                [string]$Content,
                [string]$ControlSet
            )

            $Content = $Content -replace 'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet',
                "HKEY_LOCAL_MACHINE\WIM_HKLM_SYSTEM\$ControlSet"
            $Content = $Content -replace 'HKEY_LOCAL_MACHINE\\SYSTEM',
                'HKEY_LOCAL_MACHINE\WIM_HKLM_SYSTEM'
            $Content = $Content -replace 'HKEY_LOCAL_MACHINE\\SOFTWARE',
                'HKEY_LOCAL_MACHINE\WIM_HKLM_SOFTWARE'
            $Content = $Content -replace 'HKEY_CLASSES_ROOT',
                'HKEY_LOCAL_MACHINE\WIM_HKLM_SOFTWARE\Classes'
            $Content = $Content -replace 'HKEY_CURRENT_USER',
                'HKEY_LOCAL_MACHINE\WIM_HKCU'
            $Content = $Content -replace 'HKEY_USERS\\\.DEFAULT',
                'HKEY_LOCAL_MACHINE\WIM_HKU_DEFAULT'
            return $Content
        }

        $ProcessFile = {
            param([System.IO.FileInfo]$RegFile)

            if (-not $RegFile.Exists) { return }

            # Fork: [IO.Path]::ChangeExtension is safe even when the full path
            # contains '.reg' inside a directory name. The old .Replace() would
            # mangle such paths.
            $OfflinePath = [IO.Path]::ChangeExtension($RegFile.FullName, '.Offline')

            Try {
                $Raw = Get-Content -LiteralPath $RegFile.FullName -Raw -ErrorAction Stop
                if ([String]::IsNullOrWhiteSpace($Raw)) { return }

                $Processed = & $TransformContent -Content $Raw -ControlSet $CurrentControlSet
                Set-Content -LiteralPath $OfflinePath -Value $Processed -Encoding Unicode -Force -ErrorAction Stop

                Log ($OptimizeData.ImportingRegistryTemplate -f $RegFile.Name)
                $RET = StartExe $REGEDIT -Arguments ('/S "{0}"' -f $OfflinePath)
                if ($RET -ne 0) { Throw ('regedit /S returned {0}' -f $RET) }
            }
            Catch {
                Log ($OptimizeData.FailedImportingRegistryTemplate -f $RegFile.Name) -Type Error -ErrorRecord $Error[0]
            }
            Finally {
                if (Test-Path -LiteralPath $OfflinePath) { Purge $OfflinePath -ErrorAction Ignore }
                Start-Sleep -Milliseconds 500
            }
        }

        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

        if ($Item -is [System.IO.DirectoryInfo]) {
            # Sweep stale .Offline leftovers from a previous interrupted run.
            Get-ChildItem -LiteralPath $Item.FullName -Filter *.Offline -File -ErrorAction SilentlyContinue |
                ForEach-Object { Purge $_.FullName -ErrorAction Ignore }

            Get-ChildItem -LiteralPath $Item.FullName -Filter *.reg -File -ErrorAction SilentlyContinue |
                Sort-Object -Property Name |
                ForEach-Object { & $ProcessFile -RegFile $_ }
        }
        else {
            & $ProcessFile -RegFile $Item
        }
    }
    Finally {
        if ($LoadedHere) { RegHives -Unload }
    }
}