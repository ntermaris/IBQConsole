@echo off
rem ============================================================================
rem  Rebuilds IBQConsole.res from resources\IBQConsole.rc.
rem
rem  Run this after adding an icon or changing the version information. The
rem  resulting .res is linked by the {$R *.res} in IBQConsole.lpr, so every
rem  image ships inside the executable and nothing is loaded from disk.
rem
rem  Uses fpcres rather than windres: windres shells out to the gcc
rem  preprocessor, which is not present in a plain fpcupdeluxe install, while
rem  fpcres compiles .rc files on its own.
rem ============================================================================
setlocal

set FPCRES=fpcres.exe
where %FPCRES% >nul 2>&1
if errorlevel 1 set FPCRES=C:\lazarus\fpc\bin\x86_64-win64\fpcres.exe

if not exist "%FPCRES%" (
  echo ERROR: fpcres not found. Set FPCRES in this script to its full path.
  exit /b 1
)

pushd "%~dp0\.."
"%FPCRES%" -of res -o "IBQConsole.res" "resources\IBQConsole.rc"
if errorlevel 1 (
  echo ERROR: resource compilation failed.
  popd
  exit /b 1
)
echo IBQConsole.res rebuilt.
popd
endlocal
