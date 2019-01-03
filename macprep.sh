#!/bin/bash
#
# Preparation script for MacOS VSTS build hosts
# Tested on MacOS Mojave
#

### Amend the variables below first, then run from an admin cmd.exe: sudo ~/macprep.sh -action [ACTION]
## To monitor: tail -f ~/macprep.log
###
vstsPatToken=""
vstsPool="windows-client"
vstsAgentName="macbuild"
vstsAgentUrl="https://dev.azure.com/smoothwall"
###

# Globals
vstsAgentDownloadUrl="https://vstsagentpackage.azureedge.net/agent/2.144.1/vsts-agent-osx-x64-2.144.1.tar.gz"
vstsAgentHome="$HOME/agent"

vstsAgentRoot=~/agent
vstsAgentSvcScript=$vstsAgentRoot/svc.sh
vstsAgentCfgScript=$vstsAgentRoot/config.sh
vstsAgentEnv=$vstsAgentRoot/env.sh

[ $HOME == "" ] && echo "ERROR: No HOME defined" && exit 1

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

function BrewInstall {
    echo "INFO: Install homebrew"
    
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    ReturnCodeCheck "brew_install" $?
    brew doctor
    ReturnCodeCheck "brew_doctor" $?
    
    echo "INFO: Brew update"
    brew update
    ReturnCodeCheck "brew_update" $?
}

function ConanInstall {
    echo "INFO: Install conan"
    brew update
    brew install conan
    ReturnCodeCheck "conan_install" $? 0
}

function InstallAppsBuildVsts {
    brew update
    echo "INFO: Install xcode command line tools"
    xcode-select --install
    ReturnCodeCheck "xcode-select_install" $? 1
    
    echo "INFO: Install cmake"
    brew install cmake
    ReturnCodeCheck "cmake_install" $? 0
    
    echo "INFO: Install llvm"
    brew install llvm
    ReturnCodeCheck "llvm_install" $? 0
    
    vstsAgentTar="~/vsts-agent.tar.gz"
    curl "$vstsAgentDownloadUrl" -o "$vstsAgentTar"
    ReturnCodeCheck "vsts_agent_download" $? 0
    
    mkdir "$vstsAgentHome"
    cd "$vstsAgentHome"
    tar -xf "$vstsAgentTar"
}

function InstallAppsBuildLocal {
    brew update
    echo "INFO: Install xcode command line tools"
    xcode-select --install
    ReturnCodeCheck "xcode-select_install" $? 1
    
    echo "INFO: Install cmake"
    brew install cmake
    ReturnCodeCheck "cmake_install" $? 0
    
    echo "INFO: Install llvm"
    brew install llvm
    ReturnCodeCheck "llvm_install" $? 0
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
    echo "INFO:   sudo ~/macprep.sh -Action ACTION"
    echo "INFO: Where ACTION is one of: build_local_install|vsts_config|vsts_remove|invoke"
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
            BrewInstall
            ConanInstall
            InstallAppsBuildLocal
    ;;
    #build_vsts_install)
    #    LogSet
    #    ((
    #        echo "INFO: Starting prep for VSTS build host..."
    #        BrewInstall
    #        ConanInstall
    #        InstallAppsBuildVsts
    #        OsPrepForAzure
    #        AzureVmAgentInstall
    #        VstsAgentConfig
    #
    #        echo "INFO: Done"
    #    )) *>&1 >> "$log"
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
