#!/bin/bash

echo "Azure VSTS Build Pipeline Script - macos-client-ci"

SCRIPT_VERSION="1.0.0"
BUILD_TYPE="Debug"
USE_LLVM=1
CLEAN_ENV=1

CONAN="conan"
#CONAN="C:\Program Files\Conan\conan\conan.exe"
#CMAKE_GENERATOR="Unix Makefiles"
CMAKE_GENERATOR="Xcode"

function RcCheck {
   errCode=$?
   alias=$1
    
   if [ "$errCode" ==  "0" ]
   then
      echo "INFO: OK - $alias - $errCode"
   else
      echo "INFO: Error in: $alias - $errCode"
      exit $errCode
   fi
}

[ "$Agent.HomeDirectory" == "" ] && echo "ERROR: No Agent.HomeDirectory defined" && exit 1
[ "$HOME" == "" ] && echo "ERROR: No HOME defined" && exit 1

## Uncomment line below to debug conan
# CONAN_TRACE_FILE="$Agent.HomeDirectory/conan.txt"

echo "INFO: Version: $SCRIPT_VERSION"
echo "INFO: USE_LLVM: $USE_LLVM"
echo "INFO: BUILD_TYPE: $BUILD_TYPE"
echo "INFO: CMAKE_GENERATOR: $CMAKE_GENERATOR"
echo "INFO: CLEAN_ENV: $CLEAN_ENV"

echo "INFO: Agent.HomeDirectory=$Agent.HomeDirectory"

if [ "$CLEAN_ENV" == "1" ]
then
   cacheDir="$HOME\.conan"
   echo "INFO: Remove local Conan cache: $cacheDir"
   rm -fr "$cacheDir"
else
   echo "WARN: NOT removing local Conan cache: $cacheDir"
fi

echo "INFO: Create build directory in: `pwd`"
mkdir build
cd build

RcCheck "build_mkdir"

echo "INFO: Run conan: LLVM"
"$CONAN" install .. -g cmake -s build_type="$BUILD_TYPE" --build missing

RcCheck "conan_install"

echo "INFO: Run cmake config: LLVM"
cmake .. -G "$CMAKE_GENERATOR"

RcCheck "cmake_generate"

echo "INFO: Run cmake build: $BUILD_TYPE"
cmake --build . --config "$BUILD_TYPE"

RcCheck "cmake_build"

#echo "INFO: Run: conan upload ..."
#"$CONAN" upload "*" --all -r=$REPO_REMOTE_NAME -c
#call:RcCheck "conan_upload"

exit 0