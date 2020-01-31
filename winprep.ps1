param (
	[Parameter(Mandatory=$true)][string]$action,
	[Parameter(Mandatory=$false)][string]$funcName,
	[Parameter(Mandatory=$false)][string]$funcArgs
)

$scriptVersion = "1.1.0"
#
# Windows 10 preparation script for Windows VSTS local and self-hosted build environment setup.
# Tested on Windows 10 Pro N: Version 1803 (OS Build 17134.1) and Windows Server 2016
#

### Amend the variables below first, then run from an admin cmd.exe: powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -F %USERPROFILE%\winprep.ps1 -action [ACTION]
## To monitor, tail: %USERPROFILE%\winprep.log
###
$vstsPatToken = ""
$vstsPool = "windows-client"
$vstsAgentName = ""
$vstsAgentUrl = "https://dev.azure.com/smoothwall"

## Package versions
# These are locked to a particular version, with the exception of the Azure VM agent (used for build agent hosts only).

# Chocolatey package versions (see repo: http://chocolatey.org/packages/). Note: We only use packages maintained by the respective software authors.

$vsVersion = "15.9.2.0"								# https://chocolatey.org/packages/VisualStudio2017Community
$vsWorkloadNativedesktopVersion = "1.2.1"		# https://chocolatey.org/packages/visualstudio2017-workload-nativedesktop
$cmakeVersion = "3.14.5"							# https://chocolatey.org/packages/cmake
$llvmVersion = "7.0.0"								# Not actively used by us. https://chocolatey.org/packages/llvm
$azurePipelinesAgentVersion = "2.142.1"		# https://chocolatey.org/packages/azure-pipelines-agent
$win10sdkVersion = "10.1.17763.1"				# https://chocolatey.org/packages/windows-sdk-10.1
$pythonVersion = "3.7.6"                          # https://chocolatey.org/packages/Python

$conanVersion = "1.21.1"                          # https://pypi.org/project/conan/

# Others:
$vsLlvmUrl = "https://llvmextensions.gallerycdn.vsassets.io/extensions/llvmextensions/llvm-toolchain/1.0.340780/1535663999089/llvm.vsix" # We dont currently use LLVM. https://marketplace.visualstudio.com/items?itemName=LLVMExtensions.llvm-toolchain 
$vsClangPowerToolsUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/caphyon/vsextensions/ClangPowerTools/4.10.5/vspackage"
$azureAgentUri = "https://go.microsoft.com/fwlink/?LinkID=394789" # This always pulls the latest, see: https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows

$vsixInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service\VSIXInstaller.exe" # See: https://marketplace.visualstudio.com/items?itemName=caphyon.ClangPowerTools
# Version of Visual Studio to validate when Action=build_local_install. Optionally change this to "Community".
$vsLocalType = "Professional"

# Globals
$global:log = $null

if ($vstsAgentName -eq '') {
    Hostname | Tee-Object -Variable vstsAgentName
}

function ReturnCodeCheck {
	param( [String]$alias, [String]$rcPs, [int]$rc, [int]$expectedRc )

	if ($expectedRc -eq '') {
		 $expectedRc = 0
	}

	if ($rcPs -ne $true) {
		 echo "INFO: Error processing: $alias - $rcPs != true (exitCode: $rc / $expectedRc)"
		 exit(1)
	}

	if ($rc -le $expectedRc) {
		 echo "INFO: OK - $alias - $rc <= $expectedRc - $rcPs"
	} else {
		 echo "INFO: Error processing: $alias - $rc > $expectedRc"
		 exit($rc)
	}
}

function ScriptDownloadRun {
	param( [String]$alias, [String]$uri, [int]$expectedRc)
	try {
		 $wc = New-Object net.webclient
		 $script = $wc.DownloadString($uri)
	} catch {
		 $rc = $_.Exception.Response.StatusCode.value__
		 echo "ERROR: $alias - $rc in GET: $uri"
		 exit($rc)
	}
	ReturnCodeCheck "$alias" $? $LastExitCode

	Invoke-Expression "$script"

	ReturnCodeCheck "$alias" $? $LastExitCode
}

function StartProcess {
	param( [String]$alias, [String]$process, [String[]]$argList, [int]$expectedRc)

	echo "INFO: Start process: $alias, process: $process $argList"

	$rc = Start-Process $process -Wait -PassThru -NoNewWindow -ArgumentList "$argList"
	
	ReturnCodeCheck "$alias" $? $rc.ExitCode $expectedRc
}


function TimeSync {
	echo "INFO: Set Coordinated Universal Time (UTC) time for Windows and the startup type of the Windows Time (w32time) service"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -name "RealTimeIsUniversal" -Value 1 -Type DWord -force
	
	# Try get around with: "The computer did not resync because the required time change was too big."
	&"w32tm" "/unregister"
	&"net" "stop" "w32time"
	&"w32tm" "/register"
	&"net" "start" "w32time"
	
	#Set-Service -Name W32time -StartupType Automatic
	#Stop-Service -Name W32time
	#ReturnCodeCheck "time_svc_" $? $LastExitCode

	StartProcess "time_set" w32tm "/resync /force"
}

function ChocoInstall {
	echo "INFO: Install chocolatey"

	ScriptDownloadRun "choco_install" 'https://chocolatey.org/install.ps1'
	SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
}

function DownloadUri {
	param( [String]$alias, [String]$uri, [String]$outPath)

	echo "INFO: Download task: ${alias}: $uri -> $outPath"

	try {
		 Invoke-WebRequest -Uri "$uri" -OutFile "$outPath"
		 $rc = $?
	} catch {
		 $rc = $_.Exception.Response.StatusCode.value__
	}
	
	ReturnCodeCheck "$alias" $rc $LastExitCode
}

function ConanInstall {
	echo "INFO: Install conan: $conanInstaller"
	StartProcess "conan_install" "pip3" "install conan==$conanVersion"
}

function WindowsLongPathsEnable {
	echo "INFO: Enable long paths: 260 -> 32KB"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -name "LongPathsEnabled" -Value 00000001 -Type DWord -force
	ReturnCodeCheck "conan_install_reg_long_paths_set" $? $LastExitCode
}

function DotNet35Install {
	echo "INFO: Install dotnet3.5..."
	StartProcess "choco_install_dotnet3.5" "choco" "install -y dotnet3.5" # May not always install right. TODO: Check. This may impact WiX.
}

function ChocoInstallAppsBuildVsts {

$packageConfig = @"
<?xml version="1.0" encoding="utf-8"?>

<packages>
<!-- Minimum build env -->

<package id="visualstudio2017community" version="$vsVersion" />
<package id="visualstudio2017-workload-nativedesktop" version="$vsWorkloadNativedesktopVersion" 
packageParameters="--add Microsoft.VisualStudio.Workload.NativeDesktop
 --add Microsoft.VisualStudio.Component.VC.ClangC2
 --add Microsoft.Component.MSBuild
 --add Microsoft.VisualStudio.Component.Roslyn.Compiler
 --add Microsoft.VisualStudio.Component.TextTemplating
 --add Microsoft.VisualStudio.Component.VC.CoreIde
 --add Microsoft.VisualStudio.Component.VC.Redist.14.Latest
 --add Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core
 --add Microsoft.VisualStudio.Component.Debugger.JustInTime
 --add Microsoft.VisualStudio.Component.NuGet
 --add Microsoft.VisualStudio.Component.Static.Analysis.Tools
 --add Microsoft.VisualStudio.Component.VC.ATL
 --add Microsoft.VisualStudio.Component.VC.ATLMFC
 --add Microsoft.VisualStudio.Component.VC.CMake.Project
 --add Microsoft.VisualStudio.Component.VC.DiagnosticTools
 --add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest
 --add Microsoft.VisualStudio.Component.VC.TestAdapterForGoogleTest
 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64
" />

<package id="windows-sdk-10.1" version="$win10sdkVersion" />
<package id="llvm" version="$llvmVersion" />
<package id="cmake" version="$cmakeVersion" installArguments="ADD_CMAKE_TO_PATH=System" />
<package id="git.install" />
<package id="wixtoolset" />
<package id="python" version="$pythonVersion" />

<package id="azure-pipelines-agent" version="$azurePipelinesAgentVersion" />

<package id="sysinternals" /> <!-- v.useful debug tools -->
<package id="conemu" /> <!-- Enhanced cmd.exe CLI -->
<package id="notepadplusplus.install" />
<package id="7zip" />
</packages>
"@
	$packageConfigFile = "$Env:TEMP\package-build-vsts.config"

	echo "INFO: Write chocolatey packages config: $packageConfigFile"
	$packageConfig | Out-File -FilePath "$packageConfigFile" -Encoding ASCII

	echo "INFO: Install apps via chocolatey. This may take some time"
	StartProcess "choco_install_apps" "choco" "install -y $packageConfigFile"
}

function ChocoInstallAppsBuildLocal {

$packageConfig = @"
<?xml version="1.0" encoding="utf-8"?>

<packages>
<!-- Uncomment below package to install VS community on a local build machine -->
<!-- <package id="visualstudio2017community" version="$vsVersion" /> -->

<package id="visualstudio2017-workload-nativedesktop" version="$vsWorkloadNativedesktopVersion" 
packageParameters="--add Microsoft.VisualStudio.Workload.NativeDesktop
 --add Microsoft.VisualStudio.Component.VC.ClangC2
 --add Microsoft.Component.MSBuild
 --add Microsoft.VisualStudio.Component.Roslyn.Compiler
 --add Microsoft.VisualStudio.Component.TextTemplating
 --add Microsoft.VisualStudio.Component.VC.CoreIde
 --add Microsoft.VisualStudio.Component.VC.Redist.14.Latest
 --add Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core
 --add Microsoft.VisualStudio.Component.Debugger.JustInTime
 --add Microsoft.VisualStudio.Component.NuGet
 --add Microsoft.VisualStudio.Component.Static.Analysis.Tools
 --add Microsoft.VisualStudio.Component.VC.ATL
 --add Microsoft.VisualStudio.Component.VC.ATLMFC
 --add Microsoft.VisualStudio.Component.VC.CMake.Project
 --add Microsoft.VisualStudio.Component.VC.DiagnosticTools
 --add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest
 --add Microsoft.VisualStudio.Component.VC.TestAdapterForGoogleTest
 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64
" />

<package id="windows-sdk-10.1" version="$win10sdkVersion" />
<package id="llvm" version="$llvmVersion" />
<package id="cmake" version="$cmakeVersion" installArguments="ADD_CMAKE_TO_PATH=System" />
<package id="git.install" />
<package id="wixtoolset" />
<package id="python" version="$pythonVersion" />

<package id="sysinternals" /> <!-- v.useful debug tools -->
<package id="conemu" /> <!-- Enhanced cmd.exe CLI -->
<package id="notepadplusplus.install" />
<package id="7zip" />
<package id="mobaxterm" />
</packages>
"@

	$packageConfigFile = "$Env:TEMP\package-build-local.config"

	echo "INFO: Write chocolatey packages config: $packageConfigFile"
	$packageConfig | Out-File -FilePath "$packageConfigFile" -Encoding ASCII

	echo "INFO: Install apps via chocolatey. This may take some time"
	StartProcess "choco_install_apps_local" "choco" "install -y $packageConfigFile" 1
}

function GitOptionsSet {
	echo "INFO: Set default git options"
	# We have to use the full git path, as the current PATH may not have been updated since git installation
	StartProcess "git_options_set_longpaths" "C:\Program Files\Git\cmd\git.exe" "config --system core.longpaths true"
}

function VsExtensionInstall {
	param( [String]$alias, [String]$vsType, [String]$vsExtDirName, [String]$vsExtUrl)

	$vsPlatformDir = VsExtensionDirGet $vsType
	
	$extVsix = "$Env:TEMP\$alias.vsix"
	$extVsPath = "$vsPlatformDir\$vsExtDirName"
	
	# TODO this may have to change depending on the type of extension installed
	if ((Test-Path -Path "$extVsPath") -eq $false) {
		 echo "INFO: Download VS $alias extension"
		 DownloadUri "$alias_vsix_download" "$vsExtUrl" "$extVsix"
	
		 echo "INFO: Install VS $alias extension..."

		 StartProcess "$alias_vsix_install" "$vsixInstaller" "/q $extVsix"
	} else {
		 echo "INFO: $alias VS extension appears to already be installed: $extVsPath"
	}
}

function VsDirGet {
	param( [String]$vsType)
	return "C:\Program Files (x86)\Microsoft Visual Studio\2017\$vsType"
}

function VsExtensionDirGet {
	param( [String]$vsType)
	
	$vsDir = VsDirGet $vsType
	$vsPlatformDir = "$vsDir\Common7\IDE\VC\VCTargets\Platforms\x64\PlatformToolsets\"
	
	return $vsPlatformDir
}

function ClangPowerToolsInstall {
	param([String]$vsType)

	if ( "$vsType" -eq '') {
		echo "ERROR: No vsType specified"
		exit(1);
	}
	$vsExtDirName = "TODO" # This just causes it to re-install everytime. TODO: Needs addressing.
	
	VsExtensionInstall "clang_power_tools" "$vsType" "$vsExtDirName" "$vsClangPowerToolsUrl"
}

function LlvmVsInstall {
	param( [String]$vsType)
	
	$vsPlatformDir = VsExtensionDirGet $vsType
	
	$llvmExtVsix = "$Env:TEMP\llvm.vsix"
	$llvmVsPath = "$vsPlatformDir\llvm"

	if ((Test-Path -Path "$llvmVsPath") -eq $false) {
		 echo "INFO: Download VS LLVM extension"
		 DownloadUri "llvm_vsix_download" "$vsLlvmUrl" "$llvmExtVsix"
	
		 echo "INFO: Install VS LLVM extension..."

		 StartProcess "llvm_vsix_install" "$vsixInstaller" "/q $llvmExtVsix"
	} else {
		 echo "INFO: LLVM VS extension appears to already be installed: $llvmVsPath"
	}
	
	$llvmLinkPath = "$vsPlatformDir\LLVM-vs2017"
	
	if ((Test-Path -Path "$llvmLinkPath") -eq $false) {
		 echo "INFO: Fix Conan/cmake/LLVM/VS compatibility issue..."
		 # Conan doesn't currently understand 'llvm' as a VS toolset, so we need to rename
		 
		 New-Item -Path "$llvmLinkPath" -ItemType SymbolicLink -Value "$llvmVsPath"
		 ReturnCodeCheck "llvm_mklink" $? $LastExitCode
	} else {
		 echo "INFO: LLVM VS link already exists: $llvmLinkPath"
	}
}

function WinSvcsDisable {
	$servicesDisable = @("WSearch", "spooler", "Audiosrv", "lfsvc", "DPS", "PcaSvc", "TabletInputService")
	$servicesDisable | foreach {
		 echo "INFO: Stop/Disable Windows service: $_"
		 Set-Service -Name $_ -StartupType Disabled
		 Stop-Service -Name $_
	}
}

function WinDebloatApps {
	echo "INFO: Run debloater to remove un-necessary apps. There may be a few errors here, dont worry..."
	$debloatScripts = @("Debloat Windows", "Disable Cortana", "Protect Privacy", "Remove Bloatware RegKeys", "Uninstall OneDrive")

	$debloatScripts | foreach {
		 $url = "https://raw.githubusercontent.com/Sycnex/Windows10Debloater/master/Individual Scripts/$_"
		 echo "INFO: Download/run: $url"
		 iex ((New-Object System.Net.WebClient).DownloadString($url))
	}
}

function WinDebloatSysPrep {
	echo "INFO: Run sysprep debloater. There may be a few errors here, dont worry..."
	ScriptDownloadRun "debloat_sysprep_download" 'https://raw.githubusercontent.com/Sycnex/Windows10Debloater/master/Windows10SysPrepDebloater.ps1'
}

function NugetInstall {
	echo "INFO: Install Nuget"
	Install-PackageProvider NuGet -Force
	Import-PackageProvider NuGet -Force
	ReturnCodeCheck "nuget_install" $? $LastExitCode
}

function WinDefenderAvDisable {
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -name "DisableAntiSpyware" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -name "DisableBehaviorMonitoring" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -name "DisableOnAccessProtection" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord -force
}

function OsPrepForAzure {

	### OS preparation follows...
	# Content below is cribbed from: https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image

	echo "INFO: Remove the WinHTTP proxy"
	netsh winhttp reset proxy

	echo "INFO: Set the power profile to the High Performance"
	powercfg /setactive SCHEME_MIN

	echo "INFO: Make sure that the environmental variables TEMP and TMP are set to their default values"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -name "TEMP" -Value "%SystemRoot%\TEMP" -Type ExpandString -force
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -name "TMP" -Value "%SystemRoot%\TEMP" -Type ExpandString -force

	echo "INFO: Check/reset Windows services default values"
	Set-Service -Name bfe -StartupType Automatic
	Set-Service -Name dhcp -StartupType Automatic
	Set-Service -Name dnscache -StartupType Automatic
	Set-Service -Name IKEEXT -StartupType Automatic
	Set-Service -Name iphlpsvc -StartupType Automatic
	Set-Service -Name netlogon -StartupType Manual
	Set-Service -Name netman -StartupType Manual
	Set-Service -Name nsi -StartupType Automatic
	Set-Service -Name termService -StartupType Manual
	Set-Service -Name MpsSvc -StartupType Automatic
	Set-Service -Name RemoteRegistry -StartupType Automatic

	echo "INFO: Enable RDP and set the port"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name "fDenyTSConnections" -Value 0 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "PortNumber" -Value 3389 -Type DWord -force

	echo "INFO: The listener is listening in every network interface"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "LanAdapter" -Value 0 -Type DWord -force

	echo "INFO: Set the keep-alive value"
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name "KeepAliveEnable" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name "KeepAliveInterval" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "KeepAliveTimeout" -Value 1 -Type DWord -force

	echo "INFO: Reconnect"
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name "fDisableAutoReconnect" -Value 0 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fInheritReconnectSame" -Value 1 -Type DWord -force
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fReconnectSame" -Value 0 -Type DWord -force

	echo "INFO: Limit the number of concurrent connections"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "MaxInstanceCount" -Value 4294967295 -Type DWord -force

	echo "INFO: If there are any self-signed certificates tied to the RDP listener, remove them"
	Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "SSLCertificateSHA1Hash" -force

	echo "INFO: Turn on Windows Firewall on the three profiles (Domain, Standard, and Public)"
	Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
	ReturnCodeCheck "fw_profile" $? $LastExitCode

	echo "INFO: Set network location to Private for all networks"
	$networkListManager = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}")) 
	$connections = $networkListManager.GetNetworkConnections() 
	$connections | % {$_.GetNetwork().SetCategory(1)}

	echo "INFO: Allow WinRM through the three firewall profiles (Domain, Private, and Public) and enable the PowerShell Remote service"
	Enable-PSRemoting -force
	Set-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True

	echo "INFO: Enable the following firewall rules to allow the RDP traffic"
	Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True
	ReturnCodeCheck "rdp_enable" $? $LastExitCode

	echo "INFO: Enable the File and Printer Sharing rule so that the VM can respond to a ping command inside the Virtual Network"
	Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True

	#echo "INFO: Make sure the disk is healthy and consistent, run a check disk operation at the next VM restart"
	#Chkdsk /f

	echo "INFO: Set the Boot Configuration Data (BCD) settings"
	bcdedit /set '{bootmgr}' integrityservices enable
	bcdedit /set '{default}' device partition=C:
	bcdedit /set '{default}' integrityservices enable
	bcdedit /set '{default}' recoveryenabled Off
	bcdedit /set '{default}' osdevice partition=C:
	bcdedit /set '{default}' bootstatuspolicy IgnoreAllFailures

	echo "INFO: Enable Serial Console Feature"
	bcdedit /set '{bootmgr}' displaybootmenu yes
	bcdedit /set '{bootmgr}' timeout 5
	bcdedit /set '{bootmgr}' bootems yes
	bcdedit /ems '{current}' ON
	bcdedit /emssettings EMSPORT:1 EMSBAUDRATE:115200

	echo "INFO: Setup the Guest OS to collect a kernel dump on an OS crash event"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -name CrashDumpEnabled -Type DWord -force -Value 2
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -name DumpFile -Type ExpandString -force -Value "%SystemRoot%\MEMORY.DMP"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -name NMICrashDump -Type DWord -force -Value 1

	echo "INFO: Setup the Guest OS to collect user mode dumps on a service crash event"
	$key = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
	if ((Test-Path -Path $key) -eq $false) {(New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name LocalDumps)}
	New-ItemProperty -Path $key -name DumpFolder -Type ExpandString -force -Value "c:\CrashDumps"
	New-ItemProperty -Path $key -name CrashCount -Type DWord -force -Value 10
	New-ItemProperty -Path $key -name DumpType -Type DWord -force -Value 2
	Set-Service -Name WerSvc -StartupType Manual

	echo "INFO: Verify that the Windows Management Instrumentations repository is consistent"
	winmgmt /verifyrepository
}

function AzureVmAgentInstall {
	### MS/Azure Agents
	$azureAgentMsi = "$Env:TEMP\azureVmAgent.msi";

	echo "INFO: Download Azure VM Agent"
	DownloadUri "azureAgent_download" "$azureAgentUri" "$azureAgentMsi"

	echo "INFO: Install Azure VM Agent"
	StartProcess "azureAgent_install" "msiexec" "/q /i $azureAgentMsi"
}

function VstsAgentAdminGroupAdd {
	# Required to fix Wix ICE validation failures: LGHT0217: Error executing ICE action 'ICE01'. The most common cause of this kind of ICE failure is an incorrectly registered scripting engine
	StartProcess "vstsAgent_config_netadmin" "net" 'localgroup  Administrators "NT Authority\Network Service" /add'
}

function VstsAgentConfig {
	echo "INFO: Configure VSTS Agent url/pool/agent: $vstsAgentUrl - $vstsPool - $vstsAgentName"
	StartProcess "vstsAgent_config" "c:\agent\config.cmd" "--unattended --url $vstsAgentUrl --auth pat --token $vstsPatToken --pool $vstsPool --agent $vstsAgentName --work c:\agent\_work --runAsService --acceptTeeEula --deploymentGroupTags win10,client"
	VstsAgentAdminGroupAdd
}

function VstsAgentRemove {
	echo "INFO: Remove VSTS Agent url/pool/agent: $vstsAgentUrl - $vstsPool - $vstsAgentName"
	StartProcess "vstsAgent_remove" "c:\agent\config.cmd" "remove --unattended --auth	pat --token $vstsPatToken"
}

function WindowsUpdateDisable {
	echo "INFO: Disable Windows updates"
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -name "NoAutoUpdate" -Value 1 -Type DWord -force
}

function WindowsUpdatesInstall {
	## Install Windows updates
	echo "INFO: Install Windows updates..."

	echo "INFO: Get PSWindowsUpdate command"
	Install-Module PSWindowsUpdate
	Get-Command -module PSWindowsUpdate
	ReturnCodeCheck "winUpdate_cmd_get" $? $LastExitCode

	echo "INFO: Install updates. This may take some time..."
	Install-WindowsUpdate -AcceptAll -AutoReboot
	ReturnCodeCheck "winUpdate_run" $? $LastExitCode
}

function Usage {
	echo "INFO: Amend the variables at the top of the script, then run from an admin cmd.exe:" 
	echo "INFO:	powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -F %USERPROFILE%\winprep.ps1 -Action ACTION"
	echo ""
	echo "INFO: Where ACTION is one of: build_local_install|build_vsts_install|vsts_config|vsts_remove|invoke"
	echo ""
	echo "INFO: Alternatively, separate functions defined by this script can be called via the 'invoke' action, e.g: "
	echo "INFO:  powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -F %USERPROFILE%\winprep.ps1 -Action invoke -FuncName ConanInstall"
}

function LogSet {
	Set-Variable -Name log -Value "$Env:USERPROFILE\winprep.log" -Scope Global
	echo "INFO: Logging to $log"
}

function VsCheckVersion {
  param( [String]$vsType)
  
  $vsDir = VsDirGet $vsType
  if ((Test-Path -Path $vsDir) -eq $false) {
		echo "ERROR: Please ensure Visual Studio $vsLocalType 2017 is installed and registered prior to running this install ($vsDir)"
		echo 'ERROR: When installing Visual Studio, be sure to select the "Desktop development with C++" workload to install'
		exit(1)
  }
}

switch ($action)
{
	'invoke' {
		 &$funcName $funcArgs
	}
	'timesync' { # TODO REMOVE
		 RunProc
	}
	'build_local_install' {
		 
				echo "INFO: Starting prep for local build system..."
				
				VsCheckVersion $vsLocalType
				
				ChocoInstall
				ConanInstall
				WindowsLongPathsEnable
				ChocoInstallAppsBuildLocal
				LlvmVsInstall $vsLocalType
				ClangPowerToolsInstall $vsLocalType
				GitOptionsSet

				echo "INFO: You may need to restart your shell for PATHs to take effect"
				echo "INFO: Done"
	}
	'build_vsts_install' {
		 LogSet
		 $(
				$vsLocalType = "Community"
				
				echo "INFO: Starting prep for VSTS build host..."
				
				TimeSync
				
				ChocoInstall
				ConanInstall
				WindowsLongPathsEnable
				DotNet35Install
				ChocoInstallAppsBuildVsts
				LlvmVsInstall $vsLocalType
				ClangPowerToolsInstall $vsLocalType
				GitOptionsSet
				
				WinSvcsDisable
				WinDebloatApps
				WinDebloatSysPrep
				WinDefenderAvDisable
				WindowsUpdateDisable
				NugetInstall
				OsPrepForAzure
				AzureVmAgentInstall
				VstsAgentConfig
				
				echo "INFO: You may need to restart your shell for PATHs to take effect"
				echo "INFO: Done"
		 ) *>&1 >> "$log"
	}
	'vsts_config' {
				TimeSync
				VstsAgentConfig
		 }
	'vsts_remove' {
				VstsAgentRemove
		 }
	default { Usage }

}