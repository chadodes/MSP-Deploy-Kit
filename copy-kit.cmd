@echo off
rem Called by the unattend file during the specialize pass: finds this USB
rem stick by its marker file and copies the kit to C:\OpusDeploy so that
rem post-oobe.cmd is on the machine at first sign-in. The Updates and
rem Drivers folders are NOT copied (a cumulative update is ~5 GB, and
rem driver packs can be large) - post-oobe reads both from the stick
rem directly.
for %%D in (C D E F G H I J K L) do if exist %%D:\opusdeploy.marker set SRC=%%D:
if not defined SRC exit /b 1
robocopy "%SRC%\." "C:\OpusDeploy" /E /XD "%SRC%\Updates" "%SRC%\Drivers" /NFL /NDL /NJH /NJS /R:1 /W:1 >nul 2>&1
exit /b 0
