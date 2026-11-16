Function Dismount-Image
{
    [CmdletBinding()]
    Param ()

    If (Get-WindowsImage -Mounted)
    {
        $Host.UI.RawUI.WindowTitle = $OptimizeData.ActiveMountPoints
        Write-Host $OptimizeData.ActiveMountPoints -ForegroundColor Cyan
        RegHives -Unload
        If (reg.exe query HKLM | Select-String -Pattern 'Optimize-Offline' -Quiet)
        {
            [GC]::Collect()
            reg.exe query HKLM | Select-String -Pattern 'Optimize-Offline' -Quiet | ForEach-Object -Process { [Void](StartExe $REG -Arguments ('UNLOAD {0}' -f $PSItem)) }
        }
        Get-WindowsImage -Mounted | ForEach-Object -Process {
            If ($PSItem.ImagePath -match 'boot.wim' -or $PSItem.ImagePath -match 'winre.wim' -or $PSItem.ImagePath -match 'install.wim') { [Void](Dismount-WindowsImage -Path $PSItem.MountPath -Discard) }
        }
    }
}