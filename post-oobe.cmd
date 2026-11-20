@echo off
rem ============================================================================
rem  OPUS DEPLOY - POST-OOBE FINISHING SCRIPT
rem  Runs automatically at first sign-in on the Full Auto path (via the
rem  unattend FirstLogonCommands), or run it manually once on the
rem  Settings Only path. It:
rem    - registers a resume hook (RunOnce) so that if the machine reboots
rem      mid-run, this script re-runs at the next sign-in and continues
rem    - installs any drivers found in the stick's Drivers folder with
rem      pnputil, BEFORE the join - a fresh install with no network
rem      drivers needs them before anything can reach the network
rem    - Entra-joins the machine with the client's provisioning package,
rem      then reboots ON PURPOSE to complete the join (Windows demands a
rem      restart for it; run 4 showed that restart landing mid-run when
rem      left to Windows). The resume hook picks the script up at the
rem      next sign-in and skips the join step. If the package is missing
rem      or fails, leaves a desktop note with the account to join with
rem      manually and opens the join settings page
rem    - applies per-user settings to the CURRENT user, re-applies power
rem      settings
rem    - installs the generic Apps folder, then the SELECTED CLIENT's Apps
rem    - applies the cumulative update from the stick's Updates folder,
rem      if one is there (the stick is found by its marker file), then the
rem      26H2 enablement package from the same folder
rem    - runs a Windows Update pass for everything else, then sets the
rem      timezone (after updates, so the Manitoba zone is present on the
rem      builds that only receive it through an update), and registers a
rem      finisher task that keeps re-checking at each sign-in until the
rem      machine is fully up to date
rem    - deletes the staged join packages and unattend file from the machine
rem  Everything is logged to deploy.log in this folder.
rem ============================================================================
setlocal EnableExtensions
call "%~dp0config.cmd"
setlocal EnableDelayedExpansion
set LOG=%~dp0deploy.log

echo ==== Opus post-oobe %DATE% %TIME% ==== >> "%LOG%"

if exist "%~dp0selected-client.cmd" call "%~dp0selected-client.cmd"
if defined SEL_CLIENT_DISPLAY echo  Client: %SEL_CLIENT_DISPLAY%
if not defined SEL_CLIENT_DISPLAY echo  Client: none recorded - generic finish
echo.

rem --- Find the USB stick by its marker file (Drivers + Updates live there) ----
set STICK=
for %%D in (C D E F G H I J K L) do if exist %%D:\opusdeploy.marker set STICK=%%D:

rem --- Resume hook: if the machine reboots mid-run (the join reboot does), -----
rem --- this script re-runs at the next sign-in and continues. The hook is -------
rem --- removed at the end of a complete run. ------------------------------------
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v OpusDeployResume /t REG_SZ /d "\"%~dp0post-oobe.cmd\"" /f >> "%LOG%" 2>&1
set RESUMED=
if exist "%~dp0join-done.flag" set RESUMED=1
if defined RESUMED echo  Resuming after the join restart - the join step is skipped.

rem --- Drivers from the stick's Drivers folder, BEFORE the join: a machine -----
rem --- whose fresh install has no network drivers needs them before the join ---
rem --- can register, before the package's Wi-Fi profile can connect, and -------
rem --- before the agent can check in. pnputil installs every INF it finds. -----
if defined STICK if exist "%STICK%\Drivers" (
  dir /s /b "%STICK%\Drivers\*.inf" >nul 2>&1
  if not errorlevel 1 (
    echo  Installing drivers from %STICK%\Drivers ...
    echo  Installing drivers from %STICK%\Drivers >> "%LOG%"
    pnputil /add-driver "%STICK%\Drivers\*.inf" /subdirs /install >> "%LOG%" 2>&1
    echo  Driver step done - per-driver results are in deploy.log.
  )
)

rem --- Entra ID join ------------------------------------------------------------
set "CDIR=%~dp0Clients\%SEL_CLIENT_KEY%"
set JOINED=
if defined RESUMED set JOINED=1
set "PPKGPATH=%CDIR%\%SEL_JOIN_PPKG%"
if not defined RESUMED if defined SEL_JOIN_PPKG if exist "%PPKGPATH%" (
  echo  Applying Entra join package %SEL_JOIN_PPKG% ...
  echo  Applying join package %PPKGPATH% >> "%LOG%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { Install-ProvisioningPackage -PackagePath '%PPKGPATH%' -ForceInstall -QuietInstall; exit 0 } catch { if ($_.Exception.Message -match '800700B7|-2147024713' -or $_.Exception.HResult -eq -2147024713) { exit 2 } Write-Output $_.Exception.Message; exit 1 }" >> "%LOG%" 2>&1
  set JOINCODE=!ERRORLEVEL!
  if "!JOINCODE!"=="0" set JOINED=1
  if "!JOINCODE!"=="0" set JOINAPPLIED=1
  if "!JOINCODE!"=="0" echo  Join package applied.
  if "!JOINCODE!"=="2" set JOINED=1
  if "!JOINCODE!"=="2" echo  Join package was already applied on an earlier run - counting as joined, no re-join needed.
  if "!JOINCODE!"=="2" echo  Join package already applied earlier - counted as joined. >> "%LOG%"
  if "!JOINCODE!"=="1" echo  Join package FAILED - see deploy.log. Manual join note left on the desktop.
)

rem --- Fallback: no package, or it failed - prompt for a manual join -----------
if not defined JOINED if defined SEL_JOIN_ACCOUNT (
  echo  Manual Entra join needed for %SEL_CLIENT_DISPLAY%.
  set "NOTE=%USERPROFILE%\Desktop\JOIN-ENTRA-ID.txt"
  > "!NOTE!" echo This machine still needs to be joined to Entra ID for %SEL_CLIENT_DISPLAY%.
  >>"!NOTE!" echo.
  >>"!NOTE!" echo 1. The Settings page that just opened is Access work or school.
  >>"!NOTE!" echo 2. Click Connect, then choose: Join this device to Microsoft Entra ID.
  >>"!NOTE!" echo 3. Sign in with this account:  %SEL_JOIN_ACCOUNT%
  >>"!NOTE!" echo 4. When the join finishes, restart the machine and delete this note.
  start ms-settings:workplace
)

rem --- The join needs a restart to complete - take it NOW, on our schedule, ----
rem --- instead of letting Windows fire it mid-run (run 4: its 1-minute shutdown -
rem --- landed during the agent install). The flag file makes the resumed run ---
rem --- skip the join step; the resume hook brings this script back at sign-in. --
if defined JOINAPPLIED (
  echo  Join applied. Restarting in 30 seconds to complete the join -
  echo  sign back in as %ADMIN_USER% and the finishing script resumes by itself.
  echo  Join applied - controlled restart; finishing resumes at next sign-in. >> "%LOG%"
  > "%~dp0join-done.flag" echo Join applied %DATE% %TIME%
  shutdown /r /t 30 /c "Opus deploy - restart to complete the Entra ID join; finishing resumes at sign-in"
  exit /b 0
)

echo  Applying per-user settings to %USERNAME%...
reg import "%~dp0user-current.reg" >> "%LOG%" 2>&1

echo  Power settings...
powercfg /setactive %POWER_GUID%
powercfg /change standby-timeout-ac %AC_SLEEP_MIN%
powercfg /change standby-timeout-dc %DC_SLEEP_MIN%
powercfg /change monitor-timeout-ac %AC_MONITOR_MIN%
powercfg /change monitor-timeout-dc %DC_MONITOR_MIN%
powercfg /change hibernate-timeout-ac %HIBERNATE_MIN%
powercfg /change hibernate-timeout-dc %HIBERNATE_MIN%

rem --- Generic apps (same for every client) ----------------------------------
if exist "%~dp0Apps\install-apps.cmd" (
  echo  Running Apps\install-apps.cmd...
  call "%~dp0Apps\install-apps.cmd" >> "%LOG%" 2>&1
)
for %%F in ("%~dp0Apps\*.msi") do (
  echo  Installing %%~nxF ...
  msiexec /i "%%F" /qn /norestart >> "%LOG%" 2>&1
)

rem --- Selected client's Apps folder (agent + client-specific apps) -----------
set "CDIR=%~dp0Clients\%SEL_CLIENT_KEY%"
if defined SEL_CLIENT_KEY if exist "%CDIR%\Apps\install.cmd" (
  echo  Running client Apps\install.cmd for %SEL_CLIENT_DISPLAY%...
  call "%CDIR%\Apps\install.cmd" >> "%LOG%" 2>&1
)
if defined SEL_CLIENT_KEY for %%F in ("%CDIR%\Apps\*.msi") do (
  echo  Installing client app %%~nxF ...
  msiexec /i "%%F" /qn /norestart >> "%LOG%" 2>&1
)

rem --- Updates from the USB stick's Updates folder -----------------------------
rem Cumulative update MSUs install first; the 26H2 enablement package
rem (KB5121794) installs after them, because it requires a recent cumulative
rem update (KB5124010 or later) to already be in place.
set CUFOUND=
if defined STICK for %%F in ("%STICK%\Updates\*.msu") do set CUFOUND=1
if defined CUFOUND (
  echo  Applying updates from %STICK%\Updates - this takes a while...
  echo  Applying updates from %STICK%\Updates >> "%LOG%"
  for %%F in ("%STICK%\Updates\*.msu") do (
    echo %%~nxF | findstr /i /c:"kb5121794" >nul || call :install_msu "%%F"
  )
  if exist "%STICK%\Updates\*kb5121794*.msu" (
    echo  Applying the 26H2 enablement package...
    for %%F in ("%STICK%\Updates\*kb5121794*.msu") do call :install_msu "%%F"
  )
)
if not defined CUFOUND echo  No update packages found on the stick - skipped, Windows Update will handle updates. >> "%LOG%"

rem --- Windows Update pass: everything else current ----------------------------
echo  Running Windows Update pass - checking for remaining updates...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wu-install.ps1" >> "%LOG%" 2>&1
set WUCODE=%ERRORLEVEL%
echo  Windows Update pass finished with code %WUCODE% >> "%LOG%"
if "%WUCODE%"=="3010" set REBOOTNEEDED=1

rem --- Timezone (after updates, so the Manitoba zone is present on builds ------
rem --- that only receive it through an update) ---------------------------------
echo  Timezone: %TZ_ID%
tzutil /s "%TZ_ID%" >> "%LOG%" 2>&1
set TZERR=%ERRORLEVEL%
if not "%TZERR%"=="0" (
  echo  Timezone %TZ_ID% is not present on this Windows build yet - it arrives via Windows Update. Setting interim fixed UTC-5, no DST ^(SA Pacific^) so the clock is right; switch to %TZ_ID% after updates. >> "%LOG%"
  echo  Timezone %TZ_ID% not on this build - interim UTC-5 set, see deploy.log.
  tzutil /s "SA Pacific Standard Time" >> "%LOG%" 2>&1
)

rem --- Register the update finisher: a SYSTEM task at every sign-in that -------
rem --- re-runs the WU pass until the machine is fully up to date. --------------
schtasks /create /tn "OpusDeployWU" /tr "\"%~dp0wu-finish.cmd\"" /sc onlogon /ru SYSTEM /f >> "%LOG%" 2>&1

rem --- Cleanup: never leave join packages or the unattend file behind ---------
if exist "%~dp0Clients" rmdir /s /q "%~dp0Clients" >> "%LOG%" 2>&1
if exist "C:\Windows\Panther\unattend.xml" del /q "C:\Windows\Panther\unattend.xml" >> "%LOG%" 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v OpusDeployResume /f >> "%LOG%" 2>&1
if exist "%~dp0join-done.flag" del /q "%~dp0join-done.flag" >> "%LOG%" 2>&1

echo ==== Done %DATE% %TIME% ==== >> "%LOG%"
echo.
echo  Opus post-oobe finished. Log: %LOG%

if defined REBOOTNEEDED (
  echo  Updates need a restart to finish - restarting in 60 seconds.
  echo  The update finisher keeps checking after the restart until the machine is fully up to date.
  shutdown /r /t 60 /c "Opus deploy - restart to finish updates"
)
exit /b 0

rem --- Subroutine: install one MSU from the stick with DISM --------------------
:install_msu
echo  Installing %~nx1 ...
DISM /Online /Add-Package /PackagePath:"%~1" /NoRestart >> "%LOG%" 2>&1
set DISMCODE=%ERRORLEVEL%
echo  %~nx1 finished with code %DISMCODE% >> "%LOG%"
if "%DISMCODE%"=="3010" set REBOOTNEEDED=1
exit /b 0
