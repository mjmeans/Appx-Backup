[CmdletBinding()]
param (
	[Parameter(Mandatory=$True)]
	[string] $WSAppPath,

	[Parameter(Mandatory=$True)]
	[string] $WSAppOutputPath,

	[Parameter(Mandatory=$True)]
	[string] $WSTools
)

function Run-Process {
	Param ($p, $a)
	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.FileName = $p
	$pinfo.Arguments = $a
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo
	$p.Start() | Out-Null
	$output = $p.StandardOutput.ReadToEnd()
	$output += $p.StandardError.ReadToEnd()
	$p.WaitForExit()
	return $output
}

# find tools
$FileExists = Test-Path "$WSTools\MakeAppx.exe"
if ($FileExists -eq $False) {
	Write-Output "ERROR: MakeAppx.exe not found in WSTools path."
	Exit
}
$FileExists = Test-Path "$WSTools\MakeCert.exe"
if ($FileExists -eq $False) {
	Write-Output "ERROR: MakeCert.exe not found in WSTools path."
	Exit
}
$FileExists = Test-Path "$WSTools\Pvk2Pfx.exe"
if ($FileExists -eq $False) {
	Write-Output "ERROR: Pvk2Pfx.exe not found in WSTools path."
	Exit
}
$FileExists = Test-Path "$WSTools\SignTool.exe"
if ($FileExists -eq $False) {
	Write-Output "ERROR: SignTool.exe not found in WSTools path."
	Exit
}

$WSAppXmlFile="AppxManifest.xml"

# read manifest
Write-Output "Reading ""$WSAppPath\$WSAppXmlFile"""
$FileExists = Test-Path "$WSAppPath\$WSAppXmlFile"
if ($FileExists -eq $False) {
	Write-Output "ERROR: Windows Store manifest not found."
	Exit
}
[xml]$manifest = Get-Content "$WSAppPath\$WSAppXmlFile"
$WSAppName = $manifest.Package.Identity.Name
$WSAppPublisher = $manifest.Package.Identity.Publisher
Write-Output "  App Name : $WSAppName"
Write-Output "  Publisher: $WSAppPublisher"

# prepare
$WSAppFileName = gi $WSAppPath | select basename
$WSAppFileName = $WSAppFileName.BaseName

Write-Output "Creating ""$WSAppOutputPath\$WSAppFileName.appx""."
if (Test-Path "$WSAppOutputPath\$WSAppFileName.appx") {
	Remove-Item "$WSAppOutputPath\$WSAppFileName.appx"
}
$proc = "$WSTools\MakeAppx.exe"
$args = "pack /d ""$WSAppPath"" /p ""$WSAppOutputPath\$WSAppFileName.appx"" /l"
$output = Run-Process $proc $args
if ($output -inotlike "*succeeded*") {
	Write-Output "  ERROR: Appx creation failed!"
	Write-Output "  proc = $proc"
	Write-Output "  args = $args"
	Write-Output ("  " + $output)
	Exit
}
Write-Output "  Done."

Write-Output "Creating self-signed certificates."
Write-Output "  Click NONE in the 'Create Private Key Passsword' pop-up."
if (Test-Path "$WSAppOutputPath\$WSAppFileName.pvk") {
	Remove-Item "$WSAppOutputPath\$WSAppFileName.pvk"
}
if (Test-Path "$WSAppOutputPath\$WSAppFileName.cer") {
	Remove-Item "$WSAppOutputPath\$WSAppFileName.cer"
}
$proc = "$WSTools\MakeCert.exe"
$args = "-n ""$WSAppPublisher"" -r -a sha256 -len 2048 -cy end -h 0 -eku 1.3.6.1.5.5.7.3.3 -b 01/01/2000 -sv ""$WSAppOutputPath\$WSAppFileName.pvk"" ""$WSAppOutputPath\$WSAppFileName.cer"""
$output = Run-Process $proc $args
if ($output -inotlike "*succeeded*") {
	Write-Output "ERROR: Certificate creation failed!"
	Write-Output "proc = $proc"
	Write-Output "args = $args"
	Write-Output ("  " + $output)
	Exit
}
Write-Output "  Done."

Write-Output "Converting certificate to pfx."
if (Test-Path "$WSAppOutputPath\$WSAppFileName.pfx") {
	Remove-Item "$WSAppOutputPath\$WSAppFileName.pfx"
}
$proc = "$WSTools\Pvk2Pfx.exe"
$args = "-pvk ""$WSAppOutputPath\$WSAppFileName.pvk"" -spc ""$WSAppOutputPath\$WSAppFileName.cer"" -pfx ""$WSAppOutputPath\$WSAppFileName.pfx"""
$output = Run-Process $proc $args
if ($output.Length -gt 0) {
	Write-Output "  ERROR: Certificate conversion to pfx failed!"
	Write-Output "  proc = $proc"
	Write-Output "  args = $args"
	Write-Output ("  " + $output)
	Exit
}
Write-Output "  Done."

Write-Output "Signing the package."
$proc = "$WSTools\SignTool.exe"
$args = "sign -fd SHA256 -a -f ""$WSAppOutputPath\$WSAppFileName.pfx"" ""$WSAppOutputPath\$WSAppFileName.appx"""
$output = Run-Process $proc $args
if ($output -inotlike "*successfully signed*") {
	Write-Output "ERROR: Package signing failed!"
	Write-Output $output.Length
	Write-Output "proc = $proc"
	Write-Output "args = $args"
	Write-Output ("  " + $output)
	Exit
}
Write-Output "  Done."

Remove-Item "$WSAppOutputPath\$WSAppFileName.pvk"
Remove-Item "$WSAppOutputPath\$WSAppFileName.pfx"

Write-Output "Success!"
Write-Output "  App Package: ""$WSAppOutputPath\$WSAppFileName.appx"""
Write-Output "  Certificate: ""$WSAppOutputPath\$WSAppFileName.cer"""
Write-Output "Install the '.cer' file to [Local Computer\Trusted Root Certification Authorities] before you install the App Package."
Exit
