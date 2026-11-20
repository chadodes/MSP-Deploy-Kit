@echo off
rem ============================================================================
rem  OPUS DEPLOY KIT - CONFIGURATION
rem  Edit THIS file to change deployment settings. It is the single place for:
rem  the local admin account, timezone, and power settings.
rem
rem  PASSWORD RULES: letters, digits and  @ # $ - _  only.
rem  Do NOT use  ! & < > % ^ "  in the password - they break the scripts/XML.
rem  (The ! is dropped silently by batch delayed expansion - learned the
rem  hard way on the first live test, 2026-11-17.)
rem  If you change ADMIN_PASS here, also update autounattend.xml (same value)
rem  if you ever boot from Windows install media instead of using setup.cmd.
rem ============================================================================

rem --- Local administrator account created on every deployed machine ---
set ADMIN_USER=OpusAdmin
set ADMIN_PASS=ExamplePass#2026

rem --- Timezone (must be a valid Windows timezone ID - see: tzutil /l) ---
set TZ_ID=Manitoba Standard Time

rem --- Power scheme: Balanced = 381b4222-f694-41f0-9685-ff5bb260df2e
rem ---               High performance = 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
set POWER_GUID=381b4222-f694-41f0-9685-ff5bb260df2e

rem --- Timeouts in minutes. 0 = never ---
set AC_SLEEP_MIN=0
set DC_SLEEP_MIN=15
set AC_MONITOR_MIN=10
set DC_MONITOR_MIN=5
set HIBERNATE_MIN=0
