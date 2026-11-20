@echo off
rem ============================================================================
rem  MSP DEPLOY - UPDATE FINISHER
rem  Runs from a scheduled task (created by post-oobe.cmd, running as SYSTEM
rem  at every sign-in) and re-runs the Windows Update pass (wu-install.ps1)
rem  until a pass finds the machine fully up to date; then it deletes its
rem  own task and is done. Restarts the machine when an install pass
rem  requires it. Gives up after 6 passes so a stuck update can never loop
rem  forever - if the log says it gave up, check Windows Update manually.
rem  Windows Update's own automatic updates are always the backstop anyway.
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
rem  post-oobe renames the log to deploy-<machine name>.log when a run completes;
rem  fall back to the plain name if that rename never happened (older kit, crash).
set LOG=%~dp0deploy-%COMPUTERNAME%.log
if not exist "%LOG%" if exist "%~dp0deploy.log" set LOG=%~dp0deploy.log
set COUNTFILE=%~dp0wu-passes.txt

set PASSES=0
if exist "%COUNTFILE%" set /p PASSES=<"%COUNTFILE%"
set /a PASSES+=1
>"%COUNTFILE%" echo %PASSES%
echo ==== MSP update finisher pass %PASSES% %DATE% %TIME% ==== >> "%LOG%"
if %PASSES% GTR 6 (
  echo  Finisher gave up after 6 passes - check Windows Update manually. >> "%LOG%"
  schtasks /delete /tn "MSPDeployWU" /f >> "%LOG%" 2>&1
  del /q "%COUNTFILE%" >nul 2>&1
  exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wu-install.ps1" >> "%LOG%" 2>&1
set WUCODE=%ERRORLEVEL%
echo  Finisher pass finished with code %WUCODE% >> "%LOG%"
if "%WUCODE%"=="0" (
  echo  Machine is fully up to date - finisher done, task removed. >> "%LOG%"
  schtasks /delete /tn "MSPDeployWU" /f >> "%LOG%" 2>&1
  del /q "%COUNTFILE%" >nul 2>&1
  exit /b 0
)
if "%WUCODE%"=="3010" shutdown /r /t 60 /c "MSP deploy - restart to continue updates"
exit /b 0
