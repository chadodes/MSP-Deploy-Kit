@echo off
rem ============================================================================
rem  MSP DEPLOY - run this from the Shift+F10 command prompt at the Windows
rem  setup (OOBE) screen. Pick the client, pick a mode:
rem    Mode 1 (FULL AUTO): settings applied, unattend staged, Sysprep reboot -
rem           OOBE answers itself, creates the MSP admin, and at first sign-in
rem           the machine installs the client's agent and Entra-joins using
rem           the client's provisioning package.
rem    Mode 2 (SETTINGS ONLY): settings + admin account applied, client choice
rem           recorded, but you click through OOBE yourself; run
rem           C:\MSPDeploy\post-oobe.cmd once at the desktop to finish.
rem ============================================================================
setlocal EnableExtensions
call "%~dp0config.cmd"
setlocal EnableDelayedExpansion
title MSP Deploy

echo.
echo  ============================================================
echo   MSP DEPLOY KIT
echo   Admin account : %ADMIN_USER%
echo   Timezone      : %TZ_ID%
echo  ============================================================
echo.

rem --- Find the installed Windows drive -------------------------------------
set WINDRIVE=
for %%D in (C D E F G H I J K) do (
  if exist %%D:\Windows\System32\Sysprep\sysprep.exe if exist %%D:\Users\Default\NTUSER.DAT set WINDRIVE=%%D:
)
if not defined WINDRIVE (
  echo  ERROR: Could not find the Windows installation. Nothing was changed.
  pause
  exit /b 1
)
echo  Windows found on %WINDRIVE%
echo.

rem --- Build the client menu from the Clients folders ------------------------
set IDX=0
for /d %%C in ("%~dp0Clients\*") do (
  if exist "%%C\client.cmd" (
    set /a IDX+=1
    set "CDIR_!IDX!=%%C"
    call "%%C\client.cmd"
    set "CNAME_!IDX!=!CLIENT_DISPLAY!"
  )
)
if %IDX%==0 (
  echo  ERROR: No client folders with a client.cmd were found. Nothing changed.
  pause
  exit /b 1
)

:pick_client
echo  Which client is this machine for?
echo.
for /L %%N in (1,1,%IDX%) do echo    %%N. !CNAME_%%N!
echo.
set "PICK="
set /p "PICK=  Enter number and press Enter: "
if not defined PICK goto :pick_client
set "SELDIR=!CDIR_%PICK%!"
if not defined SELDIR (
  echo  That is not on the list - try again.
  echo.
  goto :pick_client
)
for %%F in ("%SELDIR%") do set "CLIENTKEY=%%~nxF"
call "%SELDIR%\client.cmd"

echo.
echo  Selected client : %CLIENT_DISPLAY%
if defined JOIN_ACCOUNT echo  Entra join as   : %JOIN_ACCOUNT%
if not defined JOIN_ACCOUNT echo  Entra join      : none for this selection
set "PPKGPATH=%SELDIR%\%JOIN_PPKG%"
if defined JOIN_PPKG if exist "%PPKGPATH%" echo  Join package    : %JOIN_PPKG% found - join will be automatic
if defined JOIN_PPKG if not exist "%PPKGPATH%" echo  Join package    : %JOIN_PPKG% NOT in the client folder - manual join prompt at first sign-in
if exist "%SELDIR%\install.cmd" echo  Client agent    : install.cmd found
if exist "%SELDIR%\*.msi" echo  Client agent    : MSI installer found
echo.

choice /C 12 /M " 1 = Full auto - settings plus hands-free OOBE   2 = Settings only"
if errorlevel 2 goto :settings_only

rem ==========================================================================
:full_auto
call :apply_settings
call :stage_kit
call :write_selection

echo  Building unattend.xml from config.cmd values...
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content '%~dp0unattend-template.xml' -Raw).Replace('__MSP_ADMIN_USER__', $env:ADMIN_USER).Replace('__MSP_ADMIN_PASS__', $env:ADMIN_PASS) | Set-Content -Encoding UTF8 '%WINDRIVE%\Windows\Panther\unattend.xml'"
if not exist "%WINDRIVE%\Windows\Panther\unattend.xml" (
  echo  ERROR: unattend.xml was not created. Sysprep will NOT run.
  pause
  exit /b 1
)
echo.
echo  Ready. When you press a key the machine reboots and OOBE runs itself:
echo  screens answered, %ADMIN_USER% created, and at first sign-in the
echo  finishing script installs the client agent and does the Entra join.
echo  The USB stick can stay plugged in.
pause
"%WINDRIVE%\Windows\System32\Sysprep\sysprep.exe" /oobe /reboot /unattend:"%WINDRIVE%\Windows\Panther\unattend.xml"
exit /b 0

rem ==========================================================================
:settings_only
call :apply_settings
call :stage_kit
call :write_selection

echo  Creating local admin account %ADMIN_USER%...
net user %ADMIN_USER% %ADMIN_PASS% /add >nul 2>&1
if errorlevel 1 net user %ADMIN_USER% %ADMIN_PASS% >nul 2>&1
net localgroup Administrators %ADMIN_USER% /add >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-LocalUser -Name $env:ADMIN_USER -PasswordNeverExpires $true } catch {}"

echo.
echo  Done. Settings are applied and %ADMIN_USER% exists.
echo  Click through OOBE as usual - afterwards, run C:\MSPDeploy\post-oobe.cmd
echo  once from the desktop to finish: it installs the client agent and does
echo  the Entra join for %CLIENT_DISPLAY%.
pause
exit /b 0

rem ==========================================================================
:apply_settings
echo  [1/4] Machine settings - machine.reg...
reg import "%~dp0machine.reg"

echo  [2/4] Default-user settings - user.reg into the Default profile...
reg load HKLM\MSPDefault "%WINDRIVE%\Users\Default\NTUSER.DAT" >nul 2>&1
if errorlevel 1 (
  echo        WARNING: Default hive would not load - user defaults SKIPPED.
  echo        post-oobe.cmd still covers the first account; re-run setup.cmd
  echo        later from an admin prompt to fix the Default profile.
) else (
  reg import "%~dp0user.reg"
  reg unload HKLM\MSPDefault >nul 2>&1
)

echo  [3/4] Power settings...
powercfg /setactive %POWER_GUID%
powercfg /change standby-timeout-ac %AC_SLEEP_MIN%
powercfg /change standby-timeout-dc %DC_SLEEP_MIN%
powercfg /change monitor-timeout-ac %AC_MONITOR_MIN%
powercfg /change monitor-timeout-dc %DC_MONITOR_MIN%
powercfg /change hibernate-timeout-ac %HIBERNATE_MIN%
powercfg /change hibernate-timeout-dc %HIBERNATE_MIN%

if exist "%SELDIR%\libraries.reg" (
  echo  Client SharePoint libraries - libraries.reg...
  reg import "%SELDIR%\libraries.reg"
)
if exist "%SELDIR%\kfm.reg" (
  echo  Client OneDrive folder backup - kfm.reg...
  reg import "%SELDIR%\kfm.reg"
)
exit /b 0

rem ==========================================================================
:stage_kit
echo  [4/4] Copying the kit to %WINDRIVE%\MSPDeploy...
robocopy "%~dp0." "%WINDRIVE%\MSPDeploy" /E /XD "%~dp0Updates" "%~dp0Drivers" /NFL /NDL /NJH /NJS /R:1 /W:1 >nul 2>&1
if errorlevel 8 echo        WARNING: kit copy reported errors - check %WINDRIVE%\MSPDeploy
exit /b 0

rem ==========================================================================
:write_selection
rem  Records the chosen client where post-oobe.cmd will find it after OOBE.
set "SELFILE=%WINDRIVE%\MSPDeploy\selected-client.cmd"
> "%SELFILE%" echo @echo off
>>"%SELFILE%" echo set SEL_CLIENT_KEY=%CLIENTKEY%
>>"%SELFILE%" echo set SEL_CLIENT_DISPLAY=%CLIENT_DISPLAY%
>>"%SELFILE%" echo set SEL_JOIN_ACCOUNT=%JOIN_ACCOUNT%
>>"%SELFILE%" echo set SEL_JOIN_PPKG=%JOIN_PPKG%
echo  Client selection recorded for %CLIENT_DISPLAY%.
exit /b 0
