@echo off
rem --- This client's RMM agent ------------------------------------------------
rem Runs the single AGENT_*.EXE in this folder and waits for it to finish.
rem The customer-specific agent installer has its client assignment baked
rem in and installs without prompts. When you download a newer agent,
rem REPLACE the old AGENT_*.EXE - keep exactly one in this folder, or both
rem will run. Called by post-oobe.cmd during deployment; output is captured
rem in C:\OpusDeploy\deploy.log. After the installer exits, this script waits
rem a full 5 minutes: the agent's services (antivirus, monitoring) are still
rem starting after the installer process is gone, and the deployment must
rem not reboot out from under them.
setlocal EnableExtensions EnableDelayedExpansion
set FOUND=
for %%F in ("%~dp0AGENT_*.EXE") do (
  set FOUND=1
  echo Installing agent %%~nxF ...
  start /wait "" "%%F"
  echo Agent installer %%~nxF exited with code !ERRORLEVEL!.
  echo Waiting 5 minutes for the agent services to finish starting...
  ping -n 301 127.0.0.1 >nul
  echo Agent settle wait done.
)
if not defined FOUND echo No AGENT_*.EXE found in this folder - agent not installed.
endlocal
exit /b 0
