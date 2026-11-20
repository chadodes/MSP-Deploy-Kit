# MSP Deploy Kit — Windows 11 OOBE USB (v2, per-client)

Turns a brand-new or freshly reset Windows 11 laptop sitting at the setup
screen into a configured, Entra-joined machine for a specific client, with
almost no clicking:

**Shift+F10 → run `setup.cmd` → pick the client → pick Full Auto → walk
away.** The machine reboots, OOBE answers itself, your MSP admin account is
created, and at first sign-in a finishing script installs that client's RMM
agent and joins the machine to that client's Entra ID tenant.

---

## The one thing to understand about the Entra join

There is **no supported way to silently join a device to Entra ID with just
a username and password** — the join is an interactive sign-in by design,
and MFA makes stored-password joins impossible anyway. The supported
zero-touch mechanism is a **provisioning package (.ppkg) with a bulk
enrollment token**, created once per client:

- You create it in **Windows Configuration Designer** (free, from the
  Microsoft Store), signed in with your admin account **in that client's
  tenant** (e.g. `admin@example.com`). The package carries a
  bulk token tied to that tenant — no password is stored.
- At deployment, `post-oobe.cmd` applies the selected client's package and
  the device joins that tenant on its own, then reboots.
- **Bulk tokens expire** (you choose the lifetime when creating the package,
  up to ~180 days). Put a reminder on your calendar to regenerate each
  client's package before it expires, or joins will start failing and the
  kit falls back to a manual-join prompt (see below).
- If a client's package is missing or fails, the finishing script leaves a
  note on the desktop naming the account to join with, and opens
  Settings → Access work or school so you can do the 30-second manual join.
- The staged copy of the kit on the machine (including any join packages)
  is **deleted automatically** by the finishing script, so tokens don't sit
  on client hardware. The USB stick itself still holds them — treat the
  stick like a credential.

### Creating a client's join package (once per client, ~5 minutes)

1. Install **Windows Configuration Designer** from the Microsoft Store.
2. Open it → **Provision desktop devices**.
3. Name the project (e.g. the client code) → **Finish** into the editor:
   - *Set up device*: give a name pattern if you like, or skip.
   - *Set up network*: skip (or add Wi-Fi if the client needs it pre-joined).
   - *Account management*: choose **Enroll into Active Directory / Azure AD**
     → **Get a bulk token** → sign in with your admin account **in that
     client's tenant** → set the token expiry as far out as allowed.
   - *Add applications / Add certificates*: skip — the kit handles apps.
4. **Export → Provisioning package** → build it, and save the resulting
   `.ppkg` into that client's folder on this stick with the exact name
   **`join.ppkg`** (e.g. `Clients\ExampleClient\join.ppkg`).
5. The account you sign in with needs permission to join devices to that
   tenant (a Global Admin always works; the tenant's device-join settings
   must allow it).

### If "Get Bulk Token" fails in WCD (learned the hard way, Nov 2026)

WCD's embedded sign-in window often cannot complete an MFA/consent flow —
ICD.log then shows `UserInteractionRequired` / `UserCancel` and the tenant is
never actually reached (sign-ins may even show Success). Workaround: mint the
token with the **AADInternals** PowerShell module and paste it into WCD:

```powershell
Install-Module AADInternals
Import-Module AADInternals
Get-AADIntAccessTokenForAADGraph -SaveToCache
Get-AADIntAccessTokenForAADGraph -Resource urn:ms-drs:enterpriseregistration.windows.net -SaveToCache
$bprt = New-AADIntBulkPRTToken -Name "admin@<client-domain>" -Expires (Get-Date).AddDays(179)
```

Sign in as your admin account **in that client's tenant** when prompted.
Success creates a `package_<guid>` user in the tenant (check Entra Users) and
writes a `package_*-BPRT.json` file — the token is its `refresh_token` value.
In WCD switch to the **advanced editor**, go to **Accounts → Azure**, set
**Authority** to `https://login.microsoftonline.com/common`, paste the token
into the **BPRT** field, save, and export the package as `join.ppkg` as
usual. Delete the JSON afterwards — it is a credential, same as the .ppkg.

## Before first use — DO THIS

1. Open **`config.cmd`** and change `ADMIN_PASS` (default is the placeholder
   `ExamplePass#2026`). Password rules: letters, digits and `@ # $ - _` only —
never `!` (batch delayed expansion silently drops it).
2. The stick contains an admin password in plain text (that's how unattend
   files work) plus the client join tokens. Keep it with you; if you want a
   different local-admin password per client, change `config.cmd` before
   that deployment and record it in your password manager.

## Quick start (Full Auto — the normal path)

1. Copy the **contents of this folder to the root of a USB stick** (so
   `setup.cmd`, `autounattend.xml`, `mspdeploy.marker`, `Clients\` and
   `Apps\` sit at the top level).
2. Power on the laptop. At the first Windows setup screen press
   **Shift+F10** (some laptops: **Fn+Shift+F10**) for a command prompt.
3. Find the USB's drive letter — try `D:` `E:` etc. with `dir`, or run
   `wmic logicaldisk get caption`. Then run, e.g., `E:\setup.cmd`.
4. **Pick the client** from the menu (the list is built from the `Clients\`
   folders — see "Adding a client" below).
5. Choose **1 (Full Auto)**. Settings are applied, the kit and your client
   choice are staged on the machine, and on confirmation it reboots into a
   hands-free OOBE.
6. First sign-in runs `post-oobe.cmd` automatically: drivers from the
   stick's `Drivers\` folder (if any), then **the Entra join**, then a
   deliberate restart to complete the join — sign back in and the script
   resumes by itself — then per-user settings, generic apps, **the
   client's agent**, the stick's updates, a Windows Update pass, the
   timezone, the update finisher, and cleanup.
   Log file: `C:\MSPDeploy\deploy.log`.

## Settings Only mode (choice 2)

Same settings, admin account, and client selection — but no hands-free OOBE;
you click through setup yourself, then run `C:\MSPDeploy\post-oobe.cmd`
once from the desktop to finish (agent + join included). Use this for
Windows **Home** machines that still insist on a Microsoft account while
online — note Entra join needs **Pro** or better regardless.

## Adding a client

1. Copy any existing folder under `Clients\` and rename the copy to the new
   client's short code (e.g. `Clients\ACME\`). The menu picks it up
   automatically — no script edits.
2. Edit the copy's `client.cmd`: display name, `JOIN_ACCOUNT` (your admin
   account in that tenant), `JOIN_PPKG` (normally `join.ppkg`).
3. Drop the client's **`join.ppkg`** into that folder (steps above), and the
   client's **installers** (RMM agent plus any client-specific apps) into
   the folder's **`Apps\`** subfolder — an `.msi` there installs
   automatically; an EXE or a token-argument installer gets an `install.cmd`
   in that same `Apps\` subfolder with the exact command (pattern in
   `Apps\install-apps.cmd`).

Folders included as examples: **ExampleClient** (a fully worked example with a fake tenant - replace its values with your client's) and **Generic** (no client, no join). Each still
needs its `join.ppkg` and agent installer dropped in — see
`DROP-FILES-HERE.txt` in each folder.

## What gets applied

**Machine (machine.reg):** Fast Startup off · long paths on · telemetry Basic ·
Cortana off · Windows Update never auto-reboots while someone is signed in ·
verbose sign-in messages · Edge first-run skipped · automatic sign-in after an
update restart off. (Remote Desktop is in the file commented out.)

**Every user account (user.reg → Default profile, so future accounts inherit
it; user-current.reg covers the first account):** file extensions shown ·
Explorer opens at This PC · Widgets / Chat / Copilot / Task View buttons off ·
search box as icon · advertising ID off · no suggested or silently-installed
Store apps · no "finish setting up your device" nags · no Bing in Start
search · NumLock on · Game Bar capture off · no OneDrive ads in Explorer.

**Power (config.cmd):** Balanced plan · never sleeps on AC (15 min on
battery) · screen off 10 min AC / 5 min battery · hibernate never.

**Account & region (unattend):** local admin from `config.cmd` · timezone
`Manitoba Standard Time` · EULA / registration / online-account / Wi-Fi OOBE
screens hidden · network location Work.

## OneDrive & SharePoint: automatic sign-in and synced libraries

Every deployment sets two OneDrive machine policies (in `machine.reg`):
**SilentAccountConfig** — on an Entra-joined machine, the OneDrive sync app
signs itself in with the work account of whoever signs into Windows, no
setup wizard (Office apps and Edge get single sign-on from the Windows
sign-in itself); and **Files On-Demand** on, so synced libraries stay as
cloud placeholders instead of filling the disk.

To make specific SharePoint libraries appear in Explorer automatically for
a client's users, fill in that client's `libraries.reg` (a template with
step-by-step instructions is already in the ExampleClient folder; the file
is just the standard OneDrive *AutoMountTeamSites* policy). In the client's
SharePoint: open the library → **Sync** → **Copy library ID**, then add one
line per library. `setup.cmd` imports the selected client's file during
deployment whenever it exists. Notes: the user needs permission to the
library; OneDrive picks libraries up on its policy cycle, so they can take
**up to ~8 hours** after a user's first sign-in to appear; keep auto-synced
libraries under ~5,000 items.

**Folder backup (Known Folder Move)** is per client, because the policy
carries the client's tenant ID: `Clients\<CODE>\kfm.reg` silently redirects
each user's Desktop, Documents and Pictures into their OneDrive at first
sign-in (and `KFMBlockOptOut` stops them turning it back off — delete that
line if you don't want the lock). ExampleClient's file shows the format with a placeholder
tenant ID - paste in the client's real tenant ID (Entra admin center →
Identity → Overview) before it does anything. `setup.cmd` imports it the same way as
`libraries.reg`.

## Editing later

- `config.cmd` is the control panel for the shared settings: local admin,
  timezone, power. On the Full Auto path, `setup.cmd` rebuilds the unattend
  file from it automatically.
- Per-client facts live in each `Clients\<CODE>\client.cmd` — nowhere else.
- `autounattend.xml` at the stick's root is only used if you boot from
  Windows **install media** with this stick attached. If you change the
  password in `config.cmd` and also use install media, update the password
  in `autounattend.xml` too. (Install-media boots don't get the client menu —
  the menu is part of `setup.cmd`.)

## Notes & limits

- **Test on one machine first** before trusting it on a client's laptop —
  especially the first join for each tenant.
- Built for machines **at OOBE** (new, or freshly reset). Don't run Full Auto
  on a machine already in use — it re-runs OOBE via Sysprep (without
  /generalize, so drivers and Windows activation are untouched).
- **Entra join requires Windows Pro/Enterprise/Education.** Home cannot join.
- **BitLocker:** with a local account, Windows typically does not silently
  enable device encryption. If you turn BitLocker on, save the recovery key
  to the client's record right away.
- **Shift+F10 does nothing?** A few OEM images disable the OOBE command
  prompt. Fallback: boot Windows 11 install media with this stick attached —
  `autounattend.xml` still automates the OOBE half (without the client menu).
- Timezone: `Manitoba Standard Time` is the ID for Manitoba's permanent
  UTC-5. If a build doesn't know it, `post-oobe.cmd` logs the failure —
  check `tzutil /l` on that machine and update `config.cmd`.
- The eventual Microsoft-blessed version of this is **Windows Autopilot**
  (per-tenant, no expiring tokens) — worth adopting per client when a
  tenant is ready; this kit remains the no-setup fallback.

## Files

| File | Purpose |
|---|---|
| `setup.cmd` | The thing you run at Shift+F10 — client menu + modes |
| `config.cmd` | Shared settings (local admin, timezone, power) |
| `Clients\<CODE>\client.cmd` | Per-client display name, join account, package name |
| `Clients\<CODE>\join.ppkg` | That client's Entra join package (you create it) |
| `Clients\<CODE>\Apps\*.msi` / `install.cmd` | That client's agent + app installers |
| `Clients\<CODE>\libraries.reg` | That client's SharePoint libraries to auto-sync |
| `Clients\<CODE>\kfm.reg` | That client's OneDrive folder backup (Known Folder Move) |
| `machine.reg` / `user.reg` / `user-current.reg` | Registry settings |
| `unattend-template.xml` | Template `setup.cmd` fills from `config.cmd` |
| `autounattend.xml` | Pre-filled copy for install-media boots |
| `post-oobe.cmd` | First-sign-in finishing script (apps, updates, join, cleanup) |
| `wu-install.ps1` | One Windows Update pass (used by post-oobe and the finisher) |
| `wu-finish.cmd` | Update finisher — re-runs the WU pass at each sign-in until the machine is current, then removes itself |
| `copy-kit.cmd` | Helper the unattend file uses to stage the kit |
| `Apps\` | Installers shared by all clients + `install-apps.cmd` |
| `Updates\` | Latest cumulative update `.msu` + the 26H2 enablement package (KB5121794) — applied from the stick during post-oobe (not staged to the machine) |
| `mspdeploy.marker` | How the scripts find this USB stick |
