<#
  .SYNOPSIS
    Launches the Optimize-Offline GUI (Src\GUI\Start.ps1) as TrustedInstaller.

  .DESCRIPTION
    Mirrors Start-Optimize-BAU-TI.ps1 but targets the WPF GUI instead of the
    console entry point. Use when the GUI itself needs TI rights (e.g. to
    mount/optimize images that require SYSTEM-level file access).

  .NOTES
    Known limitations in SYSTEM/TI context:
      - The "Select USB" button (Out-GridView) will silently do nothing.
      - "Browse Source"/"Browse Output" dialogs default to SYSTEM's profile.
      - "Process" launches Start-Optimize.ps1 in a hidden child; the child
        inherits the TI token and runs correctly.
#>
[CmdletBinding()]
Param ()

$Global:Error.Clear()

# SYSTEM/TrustedInstaller inherits machine Restricted policy; bypass it for this process.
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Resolve this script's path (works when launched via the RunAsTI context menu,
# where $MyInvocation.MyCommand.Path is empty and args come from the command line).
$ScriptPath = $MyInvocation.MyCommand.Path
If (!$ScriptPath -and [Environment]::CommandLine -match "gc -lit '([^']+\.ps1)'") { $ScriptPath = $Matches[1] }
If (!$ScriptPath -or !(Test-Path -LiteralPath $ScriptPath)) {
    Write-Warning 'Unable to determine the location of Start-GUI-BAU-TI.ps1. Run it with: powershell -ExecutionPolicy Bypass -File <path>'
    Start-Sleep 5
    Exit
}
$ScriptRoot = Split-Path -Path $ScriptPath -Parent

# Path to the GUI entry point.
$GUIPath = Join-Path -Path $ScriptRoot -ChildPath 'Src\GUI\Start.ps1'
If (!(Test-Path -LiteralPath $GUIPath)) {
    Write-Warning ('GUI Start.ps1 not found at "{0}". Place this launcher in the module root.' -f $GUIPath)
    Start-Sleep 5
    Exit
}

# RunAsTI: C# CreateProcess core (the AveYo reflection core no longer starts processes
# on PowerShell 5.1 build 26100.9549+). Copied verbatim from Start-Optimize-BAU-TI.ps1.
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

# Build the relaunch command line for this same script.
$Relaunch = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# 1) Elevate if not admin.
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath powershell.exe -ArgumentList $Relaunch -Verb RunAs
    return
}

# 2) Become TrustedInstaller.
$IsTrustedInstaller = [Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
If (!$IsTrustedInstaller) {
    If ($env:OO_GUI_RUNASTI_RELAUNCHED) {
        Write-Warning 'Relaunched as TrustedInstaller, but this process is not running as TrustedInstaller. Stopping instead of relaunching again.'
        return
    }
    $env:OO_GUI_RUNASTI_RELAUNCHED = '1'
    $Result = RunAsTI 'powershell.exe' $Relaunch
    If ($Result -notlike 'OK*') { Write-Warning "RunAsTI failed: $Result"; Start-Sleep 5 }
    return
}

# 3) We're TrustedInstaller now — launch the GUI.
Write-Host 'Running as TrustedInstaller. Launching Optimize-Offline GUI...'
Set-Location -Path (Split-Path -Path $GUIPath -Parent)
& $GUIPath