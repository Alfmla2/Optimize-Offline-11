$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$title = 'Disable Microsoft Defender'
$firstPrompt = @'
Before continuing, install and update your third-party antivirus, then turn Tamper Protection off manually:

Windows Security > Virus & threat protection > Manage settings > Tamper Protection > Off

Select Yes only after you have turned it off. This launcher cannot change that setting for you.
'@
$answer = [System.Windows.Forms.MessageBox]::Show(
	$firstPrompt,
	$title,
	[System.Windows.Forms.MessageBoxButtons]::YesNo,
	[System.Windows.Forms.MessageBoxIcon]::Warning,
	[System.Windows.Forms.MessageBoxDefaultButton]::Button2
)
if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }

$status = Get-MpComputerStatus -ErrorAction SilentlyContinue
$tamperProperty = if ($null -ne $status) { $status.PSObject.Properties['IsTamperProtected'] } else { $null }
if ($null -ne $tamperProperty -and $status.IsTamperProtected) {
	[void][System.Windows.Forms.MessageBox]::Show(
		'Tamper Protection is still on. Turn it off in Windows Security, then launch this prompt again.',
		$title,
		[System.Windows.Forms.MessageBoxButtons]::OK,
		[System.Windows.Forms.MessageBoxIcon]::Error
	)
	exit 1
}

$secondPrompt = @'
The upstream utility will back up its current settings, make changes, and ask before restarting into Safe Mode. It will run its Safe Mode stage automatically and restart Windows back to normal mode.

Save your work before continuing. Start the utility now?
'@
$answer = [System.Windows.Forms.MessageBox]::Show(
	$secondPrompt,
	$title,
	[System.Windows.Forms.MessageBoxButtons]::YesNo,
	[System.Windows.Forms.MessageBoxIcon]::Warning,
	[System.Windows.Forms.MessageBoxDefaultButton]::Button2
)
if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }

$utilityPath = Join-Path $env:PUBLIC 'Desktop\Disable-Defender\Disable-Defender.cmd'
if (!(Test-Path -LiteralPath $utilityPath -PathType Leaf)) {
	[void][System.Windows.Forms.MessageBox]::Show(
		"The upstream utility was not found: $utilityPath",
		$title,
		[System.Windows.Forms.MessageBoxButtons]::OK,
		[System.Windows.Forms.MessageBoxIcon]::Error
	)
	exit 1
}

$arguments = '/d /c ""{0}""' -f $utilityPath
try {
	Start-Process -FilePath $env:ComSpec -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $utilityPath) -Verb RunAs -Wait -ErrorAction Stop
} catch {
	[void][System.Windows.Forms.MessageBox]::Show(
		"The utility was not started. No Defender changes were made by this launcher.`n`n$($_.Exception.Message)",
		$title,
		[System.Windows.Forms.MessageBoxButtons]::OK,
		[System.Windows.Forms.MessageBoxIcon]::Information
	)
}
