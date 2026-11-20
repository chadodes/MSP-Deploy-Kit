@echo off
rem ============================================================================
rem  OPTIONAL custom install commands - your RMM agent, antivirus, etc.
rem  post-oobe.cmd calls this file if it exists, and SEPARATELY auto-installs
rem  any *.msi files in this Apps folder silently. So:
rem    - Plain MSI agent?  Just drop the .msi in this folder, done.
rem    - EXE installer, or an MSI that needs a site key / token argument?
rem      Put the command below (remove the REM) so it runs with your switches.
rem
rem  Examples:
rem    msiexec /i "%~dp0MyAgent.msi" /qn /norestart SITEKEY=abc123
rem    "%~dp0MyAgentSetup.exe" /silent /norestart
rem ============================================================================
exit /b 0
