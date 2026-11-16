Function Get-SystemPackages {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    Param()

    $RegKeyPath = 'HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications'

    # Fork (24H2): caller MUST own the hive lifetime.
    #
    # Раньше функция делала `RegHives -Load` в начале и `RegHives -Unload` в
    # `finally`. Проблема: `Get-SystemPackages` вызывается из System App Removal,
    # где после неё идёт цикл `reg delete` по тому же hive. Функция монтировала
    # hive, читала список и размонтировала → `reg delete` в цикле видел пустой
    # hive и возвращал exit code 1 ("Failed to Remove System App").
    #
    # Новая модель:
    #   • Caller (Optimize-Offline.psm1) делает `RegHives -Load` ПЕРЕД вызовом
    #     (это уже так в обоих местах: populateLists и System App Removal).
    #   • Функция только ЧИТАЕТ hive и никогда его не размонтирует.
    #   • Caller делает `RegHives -Unload` в конце своего региона.
    #
    # `RegHives -Load` ниже оставлен как защитный no-op: если hive уже смонтирован,
    # Get-OfflineHives пропустит его; если кто-то вызовет функцию вне Optimize-
    # Offline без предварительной загрузки — hive загрузится (и останется
    # загруженным, что caller обязан размонтировать сам).
    RegHives -Load

    If (!(Test-Path -Path $RegKeyPath)) {
        return @()
    }

    # 24H2 (26100) inbox GUID → friendly-name map. These four have stayed stable
    # from RS5 through 24H2. Additional GUIDs can be added here without touching
    # the parsing loop below.
    $FriendlyNames = @{
        '1527c705-839a-4832-9118-54d4Bd6a0c89' = 'Microsoft.Windows.FilePicker'
        'c5e2524a-ea46-4f67-841f-6a9465d9d515' = 'Microsoft.Windows.FileExplorer'
        'E2A4F912-2574-4A75-9BB0-0D023378592B' = 'Microsoft.Windows.AppResolverUX'
        'F46D4000-FD22-4DB4-AC8E-4E1DDDE828FE' = 'Microsoft.Windows.AddSuggestedFoldersToLibraryDialog'
    }

    $InboxAppsPackages = Get-ChildItem -Path $RegKeyPath -Name -ErrorAction SilentlyContinue |
        ForEach-Object -Process {
            $Pkg = [String]$_

            # Inbox entries are '<Name>_<version>_<arch>_<pubhash>'. A few boxes
            # contain bare GUIDs with no underscore — guard against that.
            $Prefix = if ($Pkg -match '_') { $Pkg.Split('_')[0] } else { $Pkg }

            $Display = if ($FriendlyNames.ContainsKey($Prefix)) {
                $FriendlyNames[$Prefix]
            } else {
                $Prefix
            }

            [PSCustomObject]@{
                PackageName = $Pkg
                DisplayName = [String]$Display
            }
        } | Sort-Object -Property DisplayName, PackageName

    return $InboxAppsPackages
}