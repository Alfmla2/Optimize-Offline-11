<#
  .SYNOPSIS
    Start-Optimize is a configuration call script for the Optimize-Offline module, run as TrustedInstaller.

  .DESCRIPTION
    Relaunches itself as TrustedInstaller (if needed), imports the configuration JSON file and starts the Optimize-Offline module.
    Works when started from an admin or non-admin PowerShell, and from the "Run .PS1 as TrustedInstaller" context menu entry.

  .EXAMPLE
    .\Start-Optimize-BAU-TI.ps1
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $false)] [switch]$populateLists,
  [Parameter(Mandatory = $false)] [switch]$populateTemplates
)

$Global:Error.Clear()

# SYSTEM/TrustedInstaller falls back to the machine default policy (Restricted on Windows client), which blocks this script's module import.
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Resolve this script's path. When launched through the RunAsTI context menu the file content is run with iex, so the automatic
# variables are empty and the path has to be read from the process command line instead.
$ScriptPath = $MyInvocation.MyCommand.Path
If (!$ScriptPath -and [Environment]::CommandLine -match "gc -lit '([^']+\.ps1)'") { $ScriptPath = $Matches[1] }
If (!$ScriptPath -or !(Test-Path -LiteralPath $ScriptPath)) {
  Write-Warning 'Unable to determine the location of Start-Optimize-BAU-TI.ps1. Start it with: powershell -ExecutionPolicy Bypass -File <path>'
  Start-Sleep 5
  Exit
}
$ScriptRoot = Split-Path -Path $ScriptPath -Parent

# RunAsTI: C# CreateProcess core (the AveYo reflection core no longer starts processes on PowerShell 5.1 build 26100.9549+).
function RunAsTI ($cmd,$arg) { # Starts $cmd $arg as TrustedInstaller in a new console. Needs an elevated caller. Returns 'OK <pid>' or the failure reason.
 if (!$cmd) {$cmd='powershell'; $arg='-nop -noe'}
 if (Test-Path -LiteralPath $cmd -PathType Container) {$env:TI_DIR=$cmd; $cmd='powershell'; $arg='-nop -noe -c Set-Location -LiteralPath $env:TI_DIR'}
 elseif ($cmd -match '\.msc$') {$arg=('"{0}" {1}' -f $cmd,$arg); $cmd='mmc.exe'} elseif ($cmd -match '\.(bat|cmd)$') {$arg=('/c ""{0}" {1}"' -f $cmd,$arg); $cmd='cmd.exe'}
 if (!('RunAsTINative' -as [type])) { Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class RunAsTINative {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string r, d, t; public int x, y, xs, ys, xc, yc, fa, f; public short sw, r2; public IntPtr r3, i, o, e; }
 [StructLayout(LayoutKind.Sequential)] struct SIX { public SI s; public IntPtr a; } [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
 [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(int a, bool i, int p); [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int c, int f, ref IntPtr s); [DllImport("kernel32")] static extern void DeleteProcThreadAttributeList(IntPtr l);
 [DllImport("kernel32", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr l, int f, IntPtr a, IntPtr v, IntPtr s, IntPtr p, IntPtr r);
 [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string n, string c, IntPtr pa, IntPtr ta, bool ih, int f, IntPtr e, string d, ref SIX si, out PI pi);
 public static string Run(int parent, string cmdline) {
  IntPtr h = OpenProcess(0x0080 | 0x0040 | 0x1000, false, parent); if (h == IntPtr.Zero) return "OpenProcess(TrustedInstaller) failed, error " + Marshal.GetLastWin32Error();
  IntPtr sz = IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref sz); IntPtr l = Marshal.AllocHGlobal(sz); IntPtr hv = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(hv, h);
  try { if (!InitializeProcThreadAttributeList(l, 1, 0, ref sz) || !UpdateProcThreadAttribute(l, 0, (IntPtr)0x00020000, hv, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) return "Attribute list failed, error " + Marshal.GetLastWin32Error();
   SIX si = new SIX(); si.s.cb = Marshal.SizeOf(typeof(SIX)); si.a = l; PI pi;
   if (!CreateProcess(null, cmdline, IntPtr.Zero, IntPtr.Zero, false, 0x00080000 | 0x00000400 | 0x00000010 | 0x00000080, IntPtr.Zero, null, ref si, out pi)) return "CreateProcess failed, error " + Marshal.GetLastWin32Error();
   CloseHandle(pi.ht); CloseHandle(pi.hp); return "OK " + pi.pid; }
  finally { DeleteProcThreadAttributeList(l); Marshal.FreeHGlobal(l); Marshal.FreeHGlobal(hv); CloseHandle(h); } } }
'@ }
 [Diagnostics.Process]::EnterDebugMode(); $null = sc.exe start TrustedInstaller; $p = $null
 for ($i = 0; $i -lt 50 -and !$p; $i++) {$p = Get-Process TrustedInstaller -ea 0 | Select-Object -First 1; if (!$p) {Start-Sleep -m 100}}
 $r = if ($p) {[RunAsTINative]::Run($p.Id, ('"{0}" {1}' -f $cmd,$arg))} else {'TrustedInstaller service did not start'}
 if ($r -notlike 'OK*') {$null = (New-Object -ComObject WScript.Shell).Popup("RunAsTI failed: $r`n`n$cmd $arg",0,'RunAsTI',16)}; $r }

$arguments = @()
foreach ($param in $PSBoundParameters.GetEnumerator()) {
  $arguments += "-"+[string]$param.Key+$(If ($param.Value -notin @("True", "False")) {" "+$param.Value} Else {""})
}
$Relaunch = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$ScriptPath`" $($arguments -join ' ')"
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  # Not elevated: relaunch elevated first; the elevated copy then relaunches itself as TrustedInstaller.
  Start-Process -FilePath powershell.exe -ArgumentList $Relaunch -Verb RunAs
  return
}
$IsTrustedInstaller = [Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
If (!$IsTrustedInstaller) {
  # Never relaunch more than once: the TrustedInstaller copy inherits this variable, so a failed check cannot loop.
  If ($env:OO_RUNASTI_RELAUNCHED) {
    Write-Warning 'Relaunched as TrustedInstaller, but this process is not running as TrustedInstaller. Stopping instead of relaunching again.'
    return
  }
  # Elevated but not TrustedInstaller: start this script again as TrustedInstaller in a new console.
  $env:OO_RUNASTI_RELAUNCHED = '1'
  $Result = RunAsTI 'powershell.exe' $Relaunch
  If ($Result -notlike 'OK*') { Write-Warning "RunAsTI failed: $Result"; Start-Sleep 5 }
  return
}
# Ensure the configuration JSON file exists.
If (!(Test-Path -Path (Join-Path -Path $ScriptRoot -ChildPath Configuration.json))) {
  Write-Warning ('The required configuration JSON file does not exist: "{0}"' -f (Join-Path -Path $ScriptRoot -ChildPath Configuration.json))
  Start-Sleep 3
  Exit
}

# If the configuration JSON or ordered collection list variables still exists from a previous session, remove them.
If ((Test-Path -Path Variable:\ContentJSON) -or (Test-Path -Path Variable:\ConfigParams)) {
  Remove-Variable -Name ContentJSON, ConfigParams -ErrorAction Ignore
}

# Use a Try/Catch/Finally block in case the configuration JSON file URL formatting is invalid so we can catch it, correct its formatting and continue.
Try {
  $ContentJSON = Get-Content -Path (Join-Path -Path $ScriptRoot -ChildPath Configuration.json) -Raw | ConvertFrom-Json
}
Catch [ArgumentException] {
  $ContentJSON = (Get-Content -Path (Join-Path -Path $ScriptRoot -ChildPath Configuration.json) -Raw).Replace('\', '\\') | Set-Content -Path (Join-Path -Path $Env:TEMP -ChildPath Configuration.json) -Encoding UTF8 -Force -PassThru
  $ContentJSON = $ContentJSON | ConvertFrom-Json
  Move-Item -Path (Join-Path -Path $Env:TEMP -ChildPath Configuration.json) -Destination $ScriptRoot -Force
  $Global:Error.Remove($Error[-1])
}
Finally {
  $ContentJSON.PSObject.Properties.Remove('_Info')
}

# Convert the JSON object into a nested ordered collection list. We use the PSObject.Properties method to retain the JSON object order.
$ConfigParams = [Ordered]@{
  populateLists     = $populateLists
  populateTemplates = $populateTemplates
}
ForEach ($Name In $ContentJSON.PSObject.Properties.Name) {
  $Value = $ContentJSON.PSObject.Properties.Item($Name).Value
  If ($Value -is [PSCustomObject]) {
    $ConfigParams.$Name = [Ordered]@{ }
    ForEach ($Property in $Value.PSObject.Properties) {
      $ConfigParams.$Name[$Property.Name] = $Property.Value
    }
  }
  Else {
    $ConfigParams.$Name = $Value
  }
}

# Import the Optimize-Offline module and call it by passing the JSON configuration.
If ($PSVersionTable.PSVersion.Major -gt 5) {
  Try {
    Import-Module Dism -SkipEditionCheck -Force -WarningAction Ignore -ErrorAction Stop
  }
  Catch {
    Write-Warning 'Failed to import the required Dism module.'
    Start-Sleep 3
    Exit
  }
  Try {
    Import-Module (Join-Path -Path $ScriptRoot -ChildPath Optimize-Offline.psm1) -SkipEditionCheck -Force -WarningAction Ignore -ErrorAction Stop
  }
  Catch {
    Write-Warning ('Failed to import the Optimize-Offline module: "{0}"' -f (Join-Path -Path $ScriptRoot -ChildPath Optimize-Offline.psm1))
    Start-Sleep 3
    Exit
  }
}
Else {
  Try {
    Import-Module (Join-Path -Path $ScriptRoot -ChildPath Optimize-Offline.psm1) -Force -WarningAction Ignore -ErrorAction Stop
  }
  Catch {
    Write-Warning ('Failed to import the Optimize-Offline module: "{0}"' -f (Join-Path -Path $ScriptRoot -ChildPath Optimize-Offline.psm1))
    Start-Sleep 3
    Exit
  }
}

Optimize-Offline @ConfigParams
