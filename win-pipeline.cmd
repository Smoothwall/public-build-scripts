rem Azure VSTS Build Pipeline Script - windows-client-ci
set SCRIPT_VERSION=1.0.0

set BUILD_TYPE=Debug
set PROJECT_VERSION=1.0.0

set USE_LLVM=0
set CLEAN_ENV=1

set PROJECT_REF=%PROJECT_NAME%/%PROJECT_VERSION%@%REPO_USER%/%CONAN_CHANNEL%

set CONAN="C:\Program Files\Conan\conan\conan.exe"
set CMAKE_GENERATOR="Visual Studio 15 2017 Win64"

echo "INFO: Version: %SCRIPT_VERSION%"
echo "INFO: Project: %PROJECT_NAME%"
echo "INFO: Project.Version: %PROJECT_VERSION%"
echo "INFO: REPO_API_KEY: %REPO_API_KEY%"
echo "INFO: CONAN_CHANNEL: %CONAN_CHANNEL%"
echo "INFO: USE_LLVM: %USE_LLVM%"
echo "INFO: BUILD_TYPE: %BUILD_TYPE%"
echo "INFO: CMAKE_GENERATOR: %CMAKE_GENERATOR%"
echo "INFO: system.debug: %system.debug%"
echo "INFO: CLEAN_ENV: %CLEAN_ENV%"

echo "INFO: Remote: %REPO_USER%@%REPO_REMOTE_NAME%:%REPO_URI%"

echo "INFO: PROJECT_REF: %PROJECT_REF%"

if [%system.debug%] == [true] (
   set CONAN_TRACE_FILE=c:\agent\_work\conan.txt
   echo "INFO: Conan tracing to %CONAN_TRACE_FILE%"
)

if [%CLEAN_ENV%] == [1] (
   echo "INFO: Remove local Conan cache"
   rd /s /q "C:\Windows\ServiceProfiles\NetworkService\.conan" >NUL
   rd /s /q "C:\.conan\tmpdir" >NUL
) else (
   echo "WARN: NOT removing local Conan cache"
)

echo "INFO: Adding remote: %REPO_REMOTE_NAME%:%REPO_URI%"
%CONAN% remote add %REPO_REMOTE_NAME% %REPO_URI% --force
call:RcCheck "conan_remote_add"

echo "INFO: Adding API key for %REPO_REMOTE_NAME%"
%CONAN% user -p %REPO_API_KEY% -r %REPO_REMOTE_NAME% %REPO_USER%
call:RcCheck "conan_remote_key_add"

echo "INFO: Create build directory"
mkdir build
cd build
call:RcCheck "build_mkdir"

if [%USE_LLVM%] == [0] (
   echo "INFO: Run conan: MSVC"
   %CONAN% install .. -g visual_studio_multi -s build_type=%BUILD_TYPE% --build missing -s compiler.runtime=MDd
) else (
   echo "INFO: Run conan: LLVM"
   %CONAN% install .. -g visual_studio_multi -s build_type=%BUILD_TYPE% --build missing -s compiler.toolset=LLVM-vs2017
)
call:RcCheck "conan_install"

if [%USE_LLVM%] == [0] (
   echo "INFO: Run cmake config: MSVC"
   cmake .. -G %CMAKE_GENERATOR%
) else (
   echo "INFO: Run cmake config: LLVM"
   cmake .. -G %CMAKE_GENERATOR% -T"LLVM-vs2017"
)
call:RcCheck "cmake_generate"

echo "INFO: Run cmake build: %BUILD_TYPE%"
cmake --build . --config %BUILD_TYPE%
call:RcCheck "cmake_build"

rem echo "INFO: Run conan export: "
rem %CONAN% export . %PROJECT_REF%
rem call:RcCheck "conan_export"

rem echo "INFO: Run conan upload: %PROJECT_NAME%/%PROJECT_VERSION%@%REPO_USER%/%CONAN_CHANNEL% --all -r=%REPO_REMOTE_NAME%"
rem %CONAN% upload %PROJECT_REF% --all -r=%REPO_REMOTE_NAME%
rem echo "INFO: Run: conan upload to %REPO_REMOTE_NAME%"
rem %CONAN% upload "*" --all -r=%REPO_REMOTE_NAME% -c

call:RcCheck "conan_upload"

EXIT /B %ERRORLEVEL%

:RcCheck
   set ERRLVL=%ERRORLEVEL%
   echo "INFO: ErrorLevel:%ERRLVL%:"

   if [%ERRLVL%] == [0] (
      echo "INFO: OK - %1 - %ERRLVL%"
   ) else (
      echo "INFO: Error in: %1 - %ERRLVL%"
      exit /B %ERRLVL%
   )
goto :eof