@echo off
rem --- Example Client ---------------------------------------------
rem JOIN_ACCOUNT: the Opus admin account in this client's tenant. Used for
rem the manual-join fallback prompt, and it is the account you sign in with
rem when creating the bulk-token join package (see README).
set CLIENT_DISPLAY=Example Client
set JOIN_ACCOUNT=admin@example.com
rem JOIN_PPKG: file name of this client's Entra join provisioning package,
rem stored in this folder. Blank = no automatic join.
set JOIN_PPKG=join.ppkg
