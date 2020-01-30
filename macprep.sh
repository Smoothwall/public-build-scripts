#!/bin/bash
#
# Preparation script for MacOS VSTS build hosts
# Tested on MacOS Mojave
#

### Amend the variables below first, then run from a terminal: ~/macprep.sh -Action=ACTION
## WARNING: DO NOT RUN "build_local_install" ACTION AS ROOT OR SUDO.
###
vstsPatToken=""
vstsPool="MacOS-Clients"
vstsAgentName=""
vstsAgentUrl="https://dev.azure.com/smoothwall"
###

# Globals
vstsAgentDownloadUrl="https://vstsagentpackage.azureedge.net/agent/2.144.1/vsts-agent-osx-x64-2.144.1.tar.gz"
vstsAgentHome="$HOME/agent"

vstsAgentRoot=~/agent
vstsAgentSvcScript=$vstsAgentRoot/svc.sh
vstsAgentCfgScript=$vstsAgentRoot/config.sh
vstsAgentEnv=$vstsAgentRoot/env.sh

bashProfile=~/.bash_profile

[ "$HOME" == "" ] && echo "ERROR: No HOME defined" && exit 1
[ "$vstsAgentName" == "" ] && vstsAgentName=`hostname -s`

function ReturnCodeCheck {
	 alias=$1
	 rc=$2
	 expected=$3

	 if [ "$expected" == '' ]
	 then
		  expected=0
	 fi
	 if [ "$rc" -le "$expected" ]
	 then
		  echo "INFO: OK - $alias - $rc (<=$expected)"
	 else
		  echo "ERROR: Error processing: $alias - $rc (>$expected)"
		  exit $rc
	 fi
}

function BashProfileAdd {
	addLine=$*
	
	add=0
	if [ ! -e "$bashProfile" ]
	then
		echo "INFO: Bash profile does not exist yet: $bashProfile"
		add=1
	else
		grep "$addLine" "$bashProfile" > /dev/null
		[ "$?" != "0" ] && add=1
	fi
	
	if [ "$add" == "1" ]
	then
		echo "INFO: Add '$addLine' to: $bashProfile"
		echo "$addLine" >> "$bashProfile"
	else
		echo "INFO: Bash profile already contains: '$addLine' ($bashProfile)"
	fi
}

function BrewInstall {
	brewInstallDir=~/homebrew
	
	echo "INFO: Install homebrew in to local dir: $brewInstallDir"
	#ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
	 
	if [ ! -d "$brewInstallDir" ]
	then
		\mkdir "$brewInstallDir" 
		ReturnCodeCheck "brew_mkdir" $?
	else
		echo "Q: Homebrew already installed in $brewInstallDir, continue? (y/n)"
		read ANS
		[ "$ANS" != "y" ] && echo "No..." && exit 1
	fi
	cd "$brewInstallDir"
	
	curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$brewInstallDir"
	ReturnCodeCheck "brew_download_untar" $?
	 
	BashProfileAdd 'PATH=~/homebrew/bin:$PATH'
	 . "$bashProfile" # Source updated profile
		 
	#ReturnCodeCheck "brew_install" $?
	#brew doctor
	#ReturnCodeCheck "brew_doctor" $?
	 
	echo "INFO: Brew update"
	brew update
	ReturnCodeCheck "brew_update" $?
}

function PythonInstall {
    echo "INFO: Install Python 3 using homebrew"

    brew update
    brew install python
    ReturnCodeCheck "python_install" $?

    echo "INFO: Checking that Python command works..."
    python3 --version
    ReturnCodeCheck "python_check" $?
}

function BrewAddBashPath {
	 pkgName="$1"
	 
	 BashProfileAdd "PATH=$(brew --prefix $pkgName)/bin:\$PATH"
}

function ConanInstall {
    echo "INFO: Install conan using pip"
    pip3 install 'conan==1.21.1'
    ReturnCodeCheck "conan_install" $?
    
    echo "INFO: Checking that Conan command works..."
    conan --version
    ReturnCodeCheck "conan_check" $?
}

function InstallVstsAgent {
	 vstsAgentTar=~/vsts-agent.tar.gz
	 curl "$vstsAgentDownloadUrl" -o $vstsAgentTar
	 ReturnCodeCheck "vsts_agent_download" $? 0
	 
	 mkdir "$vstsAgentHome"
	 cd "$vstsAgentHome"
	 tar -xf "$vstsAgentTar"
}

function InstallBashNewer {
	 echo "INFO: Install GNU bash >=4"
	 brew install bash
	 ReturnCodeCheck "cmake_install" $? 0
	 
	 BrewAddBashPath bash
	 ReturnCodeCheck "bash_path_add" $?
}

function InstallXcodeCmdTools {
	 echo "INFO: Install xcode command line tools"
	 xcode-select --install
	 ReturnCodeCheck "xcode-select_install" $? 1
	 
	 echo 'INFO: If not installed, you will be prompted to install the tools in the MacOS GUI, Click "Install".'
	 echo "INFO: When complete, or if you dont see a pop-up, press enter to continue..."
	 read ANS
}

function InstallAppsBuildVsts {
	 brew update
	 
	 InstallCmake
	 InstallLlvm
	 InstallBashNewer
	 InstallAutoTools
	 
	 InstallVstsAgent
}

function InstallAppsBuildLocal {
	 brew update
		 
	 InstallCmake
	 InstallLlvm
	 InstallBashNewer
	 InstallAutoTools
}

function InstallCmake {
	 echo "INFO: Install cmake"
	 brew install cmake
	 ReturnCodeCheck "cmake_install" $? 0
	 
	 BrewAddBashPath cmake
	 ReturnCodeCheck "cmake_path_add" $?
}

function InstallLlvm {
	 echo "INFO: Install llvm"
	 brew install llvm
	 ReturnCodeCheck "brew_install_llvm" $? 0
	 
	 BrewAddBashPath llvm
	 ReturnCodeCheck "llvm_path_add" $?
}

function InstallAutoTools {
	 echo "INFO: Install: automake autoconf libtool"
	 brew install automake autoconf libtool
	 ReturnCodeCheck "brew_install_automake_autoconf" $? 0
}

function OsPrepForAzure {
	echo "INFO: Not Implemented"
}

function AzureVmAgentInstall {
	echo "INFO: Not Implemented"
}

function VstsAgentConfig {	
	 echo "INFO: Configure VSTS Agent url/pool/agent/home: $vstsAgentUrl - $vstsPool - $vstsAgentName - $vstsAgentHome"
	 $vstsAgentCfgScript "--unattended" "--url" "$vstsAgentUrl" "--auth" pat "--token" "$vstsPatToken" "--pool" "$vstsPool" "--agent" "$vstsAgentName" "--work" "$vstsAgentHome/agent/_work" "--runAsService" "--acceptTeeEula" "--deploymentGroupTags" "macos,mojave,client"
	 ReturnCodeCheck "vstsAgent_config" $?
}

function VstsAgentRemove {
	 echo "INFO: Remove VSTS Agent url/pool/agent: $vstsAgentUrl - $vstsPool - $vstsAgentName"
	 $vstsAgentCfgScript "remove" "--unattended" "--auth" "pat" "--token" "$vstsPatToken"
	 ReturnCodeCheck "vstsAgent_remove" $?
}

function Usage {
	 echo "INFO: Amend the variables at the top of the script, then run from a terminal:" 
	 echo "INFO:	~/macprep.sh -Action=ACTION"
	 echo "INFO: Where ACTION is one of: build_local_install|vsts_config|vsts_remove|invoke"
     echo ""
     echo "INFO: Do NOT run the build_local_install action as root/sudo!"
}

function LogSet {
	 log="~/macprep.log"
	 echo "INFO: Logging to $log"
}

function VstsAgentSvcInstall {
	 echo "INFO: Install service..."
	 cd "$vstsAgentRoot"
	 "$vstsAgentSvcScript" install
}

function VstsAgentSvcUninstall {
	 echo "INFO: Uninstall service..."
	 cd "$vstsAgentRoot"
	 "$vstsAgentEnv" 
	 "$vstsAgentSvcScript" uninstall
}

function VstsAgentSvcStart {
	 echo "INFO: Start service..."
	 cd "$vstsAgentRoot"
	 "$vstsAgentEnv" 
	 "$vstsAgentSvcScript" start
}

function VstsAgentSvcStop {
	 echo "INFO: Stop service..."
	 cd "$vstsAgentRoot"
	 "$vstsAgentEnv" 
	 "$vstsAgentSvcScript" stop
}

function BashProfileSource {
	. "$bashProfile"
}

for i in "$@"
do
	 case $i in
		  -Action=*)
				action="${i#*=}"
		  ;;
		  -FuncName=*)
				funcName="${i#*=}"
		  ;;
		  *)
				Usage
				exit 1
		  ;;
	 esac
done

case $action in
	 invoke)
		  $funcName
	 ;;
	 build_local_install)
				echo "INFO: Starting prep for local build system..."
				InstallXcodeCmdTools
				BrewInstall
                PythonInstall
				ConanInstall
				InstallAppsBuildLocal
				BashProfileSource
	 ;;
	 #build_vsts_install)
	 #		LogSet
	 #		((
	 #			 echo "INFO: Starting prep for VSTS build host..."
	 #			 BrewInstall
	 #			 ConanInstall
	 #			 InstallAppsBuildVsts
	 #			 OsPrepForAzure
	 #			 #AzureVmAgentInstall
	 #			 VstsAgentConfig
	 #
	 #			 echo "INFO: Done"
	 #		)) *>&1 >> "$log"
	 #}
	 vsts_config)
				VstsAgentConfig
				VstsAgentSvcInstall
				VstsAgentSvcStart
	 ;;
	 vsts_remove)
				VstsAgentSvcStop
				VstsAgentSvcUninstall
				VstsAgentRemove
	 ;;
	 *)
				Usage
				exit 1
	 ;;
esac
