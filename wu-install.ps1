# ============================================================================
#  MSP DEPLOY - WINDOWS UPDATE PASS
#  Searches Windows Update for applicable software updates (driver updates
#  excluded - they are the optional class; feature updates excluded by
#  title - version jumps are a separate decision), downloads them, then
#  installs them ONE AT A TIME, logging each update's result as it lands,
#  so deploy.log shows progress instead of going silent for 30-60 minutes
#  while a big cumulative update installs. Called by post-oobe.cmd and by
#  the wu-finish.cmd finisher.
#  Exit codes: 0 = fully up to date, 2 = installed (no restart needed),
#  3010 = installed (restart required), 3 = pass failed or incomplete.
#  A failed pass never fails the deployment - Windows Update's own
#  automatic updates remain as the backstop.
# ============================================================================
try {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    Write-Output "Searching Windows Update for applicable updates..."
    $found = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0").Updates
    $updates = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $found) {
        if ($u.Title -like "Feature update*") {
            Write-Output ("Skipping feature update (version upgrades are a separate decision): " + $u.Title)
            continue
        }
        [void]$updates.Add($u)
    }
    if ($updates.Count -eq 0) {
        Write-Output "No applicable updates - machine is up to date."
        exit 0
    }
    Write-Output ("Installing " + $updates.Count + " update(s):")
    foreach ($u in $updates) {
        Write-Output (" - " + $u.Title)
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
    }
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $dl = $downloader.Download()
    Write-Output ("Download result: " + $dl.ResultCode + " (2 = succeeded)")
    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $updates) { if ($u.IsDownloaded) { [void]$ready.Add($u) } }
    if ($ready.Count -eq 0) {
        Write-Output "No updates downloaded successfully - will retry on a later pass."
        exit 3
    }
    # Install one update at a time so the log shows each one landing.
    # If an install says a restart is required, stop here: the remaining
    # updates are picked up by the finisher after the reboot, and installing
    # on past a pending restart is unreliable.
    $anyInstalled = $false
    $anyFailed = $false
    $rebootRequired = $false
    for ($i = 0; $i -lt $ready.Count; $i++) {
        $u = $ready.Item($i)
        Write-Output ("Installing (" + ($i + 1) + "/" + $ready.Count + "): " + $u.Title)
        $single = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$single.Add($u)
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $single
        $inst = $installer.Install()
        $code = $inst.GetUpdateResult(0).ResultCode
        Write-Output (" - " + $u.Title + " => result " + $code + " (2 = succeeded, 3 = succeeded with errors, 4 = failed, 5 = aborted)")
        if ($code -eq 2 -or $code -eq 3) { $anyInstalled = $true }
        if ($code -eq 4 -or $code -eq 5) { $anyFailed = $true }
        if ($inst.RebootRequired) {
            Write-Output "A restart is required to finish installing updates - stopping this pass here; the finisher picks up the rest after the reboot."
            $rebootRequired = $true
            break
        }
    }
    if ($rebootRequired) { exit 3010 }
    if ($anyFailed -and -not $anyInstalled) { exit 3 }
    exit 2
} catch {
    Write-Output ("Windows Update pass failed: " + $_.Exception.Message)
    exit 3
}
