Function Test-InteractiveGridView
{
    <#
    .SYNOPSIS
        Проверяет, можно ли использовать Out-GridView в текущей сессии.
    .DESCRIPTION
        Out-GridView требует одновременно три условия:
          1) интерактивный рабочий стол (не Session 0 / SYSTEM);
          2) присутствие сборки Microsoft.PowerShell.GraphicalHost,
             которая ставится вместе с компонентом "Windows PowerShell ISE";
          3) наличие самого cmdlet Out-GridView в текущем хосте.

        Если чего-то нет, вызов Out-GridView бросает исключение, но модуль
        Optimize-Offline выставляет $ErrorActionPreference = 'SilentlyContinue',
        и исключение глушится, превращаясь в $null. Из-за этого вызывающий
        код не может отличить "пользователь нажал Cancel" от "диалог не открылся".
        Эта функция нужна, чтобы различить два случая до вызова Out-GridView.
    .PARAMETER Detailed
        Вернуть PSCustomObject с полями .Available и .Reason вместо [bool].
    .OUTPUTS
        System.Boolean — либо PSCustomObject при -Detailed.
    .EXAMPLE
        if (-not (Test-InteractiveGridView)) { Write-Warning 'Нет GUI' }
    .EXAMPLE
        $s = Test-InteractiveGridView -Detailed
        if (-not $s.Available) { Write-Warning $s.Reason }
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter()]
        [Switch]$Detailed
    )

    $Result = [PSCustomObject]@{
        Available = $true
        Reason    = $null
    }

    # 1) Интерактивная сессия
    If (-not [Environment]::UserInteractive)
    {
        $Result.Available = $false
        $Result.Reason    = 'the current session is not interactive (Environment.UserInteractive is False).'
    }

    # 2) Session 0 => SYSTEM / служба; GUI недостижим
    If ($Result.Available)
    {
        $SessionId = $null
        Try { $SessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId } Catch { Write-Debug $_.Exception.Message }
        If ($null -ne $SessionId -and $SessionId -eq 0)
        {
            $Result.Available = $false
            $Result.Reason    = 'the current process runs in Session 0 (SYSTEM / service context); no GUI is reachable.'
        }
    }

    # 3) Cmdlet Out-GridView должен существовать в текущем хосте
    If ($Result.Available)
    {
        If (-not (Get-Command -Name Out-GridView -ErrorAction Ignore))
        {
            $Result.Available = $false
            $Result.Reason    = 'the Out-GridView cmdlet is not available in the current host.'
        }
    }

    # 4) Сборка Microsoft.PowerShell.GraphicalHost (ставится вместе с ISE)
    If ($Result.Available)
    {
        Try
        {
            Add-Type -AssemblyName Microsoft.PowerShell.GraphicalHost -ErrorAction Stop
        }
        Catch
        {
            $Result.Available = $false
            $Result.Reason    = ('the assembly Microsoft.PowerShell.GraphicalHost is not installed ' +
                                '(the "Windows PowerShell ISE" optional feature is missing).')
        }
    }

    If ($Detailed)
    {
        return $Result
    }

    return [bool]$Result.Available
}