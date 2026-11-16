Function Start-Executable
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param
    (
        [Parameter(Mandatory = $true)]
        [IO.FileInfo]$Executable,
        [String[]]$Arguments
    )

    Begin
    {
        if ($PSCmdlet.ShouldProcess($Executable.FullName, "Start executable"))
        {
            $ProcessInfo = New-Object -TypeName Diagnostics.ProcessStartInfo -ErrorAction:$ErrorActionPreference
            $ProcessInfo.FileName = $Executable.FullName
            If (![String]::IsNullOrEmpty($Arguments)) { $ProcessInfo.Arguments = $Arguments }
            $ProcessInfo.CreateNoWindow = $true
            $ProcessInfo.WindowStyle = 'Hidden'
            $ProcessInfo.UseShellExecute = $false
            $ProcessRun = New-Object -TypeName Diagnostics.Process -ErrorAction:$ErrorActionPreference
            $ProcessRun.StartInfo = $ProcessInfo
        }
    }
    Process
    {
        if ($null -ne $ProcessRun)
        {
            [Void]$ProcessRun.Start()
            $ProcessRun.WaitForExit()
            $ProcessRun.ExitCode
        }
    }
    End
    {
        If ($null -ne $ProcessRun) { $ProcessRun.Dispose() }
    }
}