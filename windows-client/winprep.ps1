param (
    [Parameter(Mandatory=$true)][string]$action
)
#
# Windows 10 preparation script for Windows VSTS build hosts
# Tested on Windows 10 Pro N: Version 1803 (OS Build 17134.1)
#

### Amend the variables below first, then run from an admin cmd.exe: powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -F %USERPROFILE%\winprep.ps1 -action [ACTION]
## To monitor, tail: %USERPROFILE%\winprep.log
###
$vstsPatToken = ""
$vstsPool = "windows-client"
$vstsAgentName = "winbuild"
$vstsAgentUrl = "https://dev.azure.com/smoothwall"
###

# Globals
$global:log = $null

function ReturnCodeCheck {
    param( [String]$alias, [int]$rc, [int]$expected )

    if ($expected -eq '') {
        $expected = 0
    }
    if ($rc -le $expected) {
        echo "INFO: OK - $alias - $rc (<=$expected)"
    } else {
        echo "INFO: Error processing: $alias - $rc (>$expected)"
        exit($rc)
    }
}

function TimeSync {
    echo "INFO: Set Coordinated Universal Time (UTC) time for Windows and the startup type of the Windows Time (w32time) service"
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -name "RealTimeIsUniversal" -Value 1 -Type DWord -force
    Set-Service -Name W32time -StartupType Automatic
    Restart-Service -Name W32time
    &"w32tm" "/resync" "/force"
    ReturnCodeCheck "time_set" $? 1
}

function ChocoInstall {
    echo "INFO: Install chocolatey"
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    ReturnCodeCheck "choco_install" $LastExitCode

    SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
}

function ConanInstall {
    $conanInstaller = "$Env:TEMP\conanInstaller.exe";
    $conanInstallUri = "https://dl.bintray.com/conan/installers/conan-win-64_1_10_1.exe"

    # Fix powershell stupidity: https://stackoverflow.com/a/39736671 i.e problems downloading from certain URIs
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    echo "INFO: Download conan: $conanInstallUri -> $conanInstaller"
    Invoke-WebRequest -Uri "$conanInstallUri" -OutFile "$conanInstaller"
    ReturnCodeCheck "conan_download" $LastExitCode

    echo "INFO: Install conan: $conanInstaller"
    &"$conanInstaller" "/SILENT"
    ReturnCodeCheck "conan_install" $? 1 # Installer always returns 1 for some reason
}

function DotNet35Install {
    echo "INFO: Install dotnet3.5..."
    &"choco" "install" "-y" "dotnet3.5"
    ReturnCodeCheck "choco_install_dotnet3.5" $? 1
}

function ChocoInstallAppsBuildVsts {

$packageConfig = @"
<?xml version="1.0" encoding="utf-8"?>

<packages>
<!-- Minimum build env -->

<package id="visualstudio2017community" version="15.9.2.0" />
<package id="visualstudio2017-workload-nativedesktop" version="1.2.1" 
packageParameters="--add Microsoft.VisualStudio.Workload.NativeDesktop --no-includeRecommended --no-includeOptional
--add Microsoft.VisualStudio.Component.VC.ClangC2
--add Microsoft.Component.MSBuild MSBuild
--add Microsoft.VisualStudio.Component.Roslyn.Compiler
--add Microsoft.VisualStudio.Component.TextTemplating
--add Microsoft.VisualStudio.Component.VC.CoreIde
--add Microsoft.VisualStudio.Component.VC.Redist.14.Latest
--add Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core
--add Microsoft.VisualStudio.Component.Debugger.JustInTime
--add Microsoft.VisualStudio.Component.NuGet
--add Microsoft.VisualStudio.Component.Static.Analysis.Tools
--add Microsoft.VisualStudio.Component.VC.ATL Visual
--add Microsoft.VisualStudio.Component.VC.CMake.Project
--add Microsoft.VisualStudio.Component.VC.DiagnosticTools
--add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest
--add Microsoft.VisualStudio.Component.VC.TestAdapterForGoogleTest
--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64
--add Microsoft.VisualStudio.Component.Windows10SDK.17134 
" />
<package id="llvm" version="7.0.0" />
<package id="cmake" version="3.13.1" installArguments="ADD_CMAKE_TO_PATH=System" />
<package id="git.install" />
<package id="wixtoolset" />

<package id="azure-pipelines-agent" version="2.142.1" />

<package id="notepadplusplus.install" />
<package id="sysinternals" /> <!-- v.useful debug tools -->
<package id="conemu" /> <!-- Enhanced cmd.exe CLI -->
</packages>
"@
    $packageConfigFile = "$Env:USERPROFILE\package-build-vsts.config"

    echo "INFO: Write chocolatey packages config: $packageConfigFile"
    $packageConfig | Out-File -FilePath "$packageConfigFile" -Encoding ASCII

    echo "INFO: Install apps via chocolatey. This may take some time"
    cinst -y "$packageConfigFile"
    ReturnCodeCheck "choco_install_apps" $? 1
}

function ChocoInstallAppsBuildLocal {

$packageConfig = @"
<?xml version="1.0" encoding="utf-8"?>

<packages>
<!-- Minimum build env -->

<package id="visualstudio2017-workload-nativedesktop" version="1.2.1" 
packageParameters="--add Microsoft.VisualStudio.Workload.NativeDesktop --no-includeRecommended --no-includeOptional
--add Microsoft.VisualStudio.Component.VC.ClangC2
--add Microsoft.Component.MSBuild MSBuild
--add Microsoft.VisualStudio.Component.Roslyn.Compiler
--add Microsoft.VisualStudio.Component.TextTemplating
--add Microsoft.VisualStudio.Component.VC.CoreIde
--add Microsoft.VisualStudio.Component.VC.Redist.14.Latest
--add Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core
--add Microsoft.VisualStudio.Component.Debugger.JustInTime
--add Microsoft.VisualStudio.Component.NuGet
--add Microsoft.VisualStudio.Component.Static.Analysis.Tools
--add Microsoft.VisualStudio.Component.VC.ATL Visual
--add Microsoft.VisualStudio.Component.VC.CMake.Project
--add Microsoft.VisualStudio.Component.VC.DiagnosticTools
--add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest
--add Microsoft.VisualStudio.Component.VC.TestAdapterForGoogleTest
--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64
--add Microsoft.VisualStudio.Component.Windows10SDK.17134 
" />
<package id="llvm" version="7.0.0" />
<package id="cmake" version="3.13.1" installArguments="ADD_CMAKE_TO_PATH=System" />
<package id="git.install" />
<package id="wixtoolset" />

<package id="notepadplusplus.install" />
<package id="sysinternals" /> <!-- v.useful debug tools -->
<package id="conemu" /> <!-- Enhanced cmd.exe CLI -->
</packages>
"@
    $packageConfigFile = "$Env:TEMP\package-build-local.config"

    echo "INFO: Write chocolatey packages config: $packageConfigFile"
    $packageConfig | Out-File -FilePath "$packageConfigFile" -Encoding ASCII

    echo "INFO: Install apps via chocolatey. This may take some time"
    cinst -y "$packageConfigFile"
    ReturnCodeCheck "choco_install_apps_local" $? 1
}

function LlvmVsInstall {
    $llvmExtVsix = "$Env:TEMP\llvm.vsix"
    $vsLlvmUrl = "https://llvmextensions.gallerycdn.vsassets.io/extensions/llvmextensions/llvm-toolchain/1.0.340780/1535663999089/llvm.vsix"
    echo "INFO: Download VS LLVM extension: $vsLlvmUrl -> $llvmExtVsix"
    Invoke-WebRequest -Uri "$vsLlvmUrl" -OutFile "$llvmExtVsix" -MaximumRedirection 0 -ErrorAction Ignore
    ReturnCodeCheck "llvm_vsix_download" $LastExitCode

    echo "INFO: Install VS LLVM extension..."
    $vsixInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service\VSIXInstaller.exe"
    &"$vsixInstaller" "/q" "$llvmExtVsix"
    ReturnCodeCheck "llvm_vsix_install" $?

    echo "INFO: Fix Conan/cmake/LLVM/VS compatibility issue..."
    # Conan doesn't currently understand 'llvm' as a VS toolset, so we need to rename
    $vsPlatformDir = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\IDE\VC\VCTargets\Platforms\x64\PlatformToolsets\"
    cmd /c mklink /D "$vsPlatformDir\LLVM-vs2017" "$vsPlatformDir\llvm"
    ReturnCodeCheck "llvm_mklink" $?
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
    iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Sycnex/Windows10Debloater/master/Windows10SysPrepDebloater.ps1'))
    ReturnCodeCheck "debloat_sysprep_download" $LastExitCode
}

function NugetInstall {
    echo "INFO: Install Nuget"
    Install-PackageProvider NuGet -Force
    Import-PackageProvider NuGet -Force
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
    ReturnCodeCheck "fw_profile" $LastExitCode

    echo "INFO: Set network location to Private for all networks"
    $networkListManager = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}")) 
    $connections = $networkListManager.GetNetworkConnections() 
    $connections | % {$_.GetNetwork().SetCategory(1)}

    echo "INFO: Allow WinRM through the three firewall profiles (Domain, Private, and Public) and enable the PowerShell Remote service"
    Enable-PSRemoting -force
    Set-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True

    echo "INFO: Enable the following firewall rules to allow the RDP traffic"
    Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True
    ReturnCodeCheck "rdp_enable" $LastExitCode

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
    echo "INFO: Download Azure VM Agent to: $azureAgentMsi"
    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?LinkID=394789" -OutFile "$azureAgentMsi"
    ReturnCodeCheck "azureAgent_download" $LastExitCode

    echo "INFO: Install Azure VM Agent"
    msiexec /i "$azureAgentMsi" /q
    ReturnCodeCheck "azureAgent_install" $?
}

function VstsAgentConfig {
    echo "INFO: Configure VSTS Agent url/pool/agent: $vstsAgentUrl - $vstsPool - $vstsAgentName"
    c:\agent\config.cmd "--unattended" "--url" "$vstsAgentUrl" "--auth" pat "--token" "$vstsPatToken" "--pool" "$vstsPool" "--agent" "$vstsAgentName" "--work" "c:\agent\_work" "--runAsService" "--acceptTeeEula" "--deploymentGroupTags" "win10, client"
    ReturnCodeCheck "vstsAgent_config" $?
}

function VstsAgentRemove {
    echo "INFO: Remove VSTS Agent url/pool/agent: $vstsAgentUrl - $vstsPool - $vstsAgentName"
    c:\agent\config.cmd "remove" "--unattended" "--auth" "pat" "--token" "$vstsPatToken"
    ReturnCodeCheck "vstsAgent_remove" $?
}

function WindowsUpdatesInstall {
    ## Install Windows updates
    echo "INFO: Install Windows updates..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Import-PackageProvider NuGet -Force
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    ReturnCodeCheck "nuget_install" $LastExitCode

    echo "INFO: Get PSWindowsUpdate command"
    Install-Module PSWindowsUpdate
    Get-Command -module PSWindowsUpdate
    ReturnCodeCheck "winUpdate_cmd_get" $LastExitCode

    echo "INFO: Install updates. This may take some time..."
    Install-WindowsUpdate -AcceptAll -AutoReboot
    ReturnCodeCheck "winUpdate_run" $LastExitCode
}

function Usage {
    echo "INFO: Amend the variables at the top of the script, then run from an admin cmd.exe:" 
    echo "INFO:   powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -F %USERPROFILE%\winprep.ps1 -Action ACTION"
    echo "INFO: Where ACTION is one of: build_local_install|build_vsts_install|vsts_config|vsts_remove"
}

function LogSet {
    Set-Variable -Name log -Value "$Env:USERPROFILE\winprep.log" -Scope Global
    echo "INFO: Logging to $log"
}

switch ($action)
{
    'build_local_install' {
        
            echo "INFO: Starting prep for local build system..."
			ChocoInstall
            ConanInstall
            ChocoInstallAppsBuildLocal
            LlvmVsInstall
       
    }
    'build_vsts_install' {
        LogSet
        $(
            echo "INFO: Starting prep for VSTS build host..."
            TimeSync
            ChocoInstall
            ConanInstall
            DotNet35Install
            ChocoInstallAppsBuildVsts
            LlvmVsInstall
            WinSvcsDisable
            WinDebloatApps
            WinDebloatSysPrep
            NugetInstall
            OsPrepForAzure
            AzureVmAgentInstall
            VstsAgentConfig
            WindowsUpdatesInstall

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