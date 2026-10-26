# Installer migration test boundary and next preview plan

## Current disposition

The locally built 0.4.5 candidate is local-only. Do not replace existing 0.4.5
release assets, reuse the windows-v0.4.5 tag, publish its manifest, or install it on
the user's current PC. Its hashes/provenance remain in the task's CANDIDATE.json.

## Why a different folder is insufficient

Reviewed the actual pinned electron-builder 26.15.3 NSIS source:

- `multiUser.nsh` defines registry keys from APP_GUID and reads InstallLocation.
- `installSection.nsh` invokes CHECK_APP_RUNNING, uninstallOldVersion and
  registryAddInstallInfo, before adding desktop/Start Menu links.
- `include/installUtil.nsh` reads the previous UninstallString by shared identity.
- `include/installer.nsh` writes InstallLocation, ShortcutName, DisplayName and
  uninstall commands. Shortcut migration can rename/remove old links.
- `include/allowOnlyOneInstallerInstance.nsh` contains executable-name based
  process detection/termination using APP_EXECUTABLE_FILENAME (`Plaza.exe`).

`/D`, `/S`, a temporary extracted directory, and Electron's --user-data-dir do not
isolate these installer actions. Redirecting APPDATA also does not isolate the
Windows registry or process matching. A different appId/executable could make a
separate smoke-test package, but it would not validate this real upgrade identity.
Do not run `test:updates` against this user's computer: it installs/reinstalls a
baseline, replaces an installed app, launches it and terminates fixture processes.

## Required environment for actual migration acceptance

Use a disposable Windows VM (or equivalent separate disposable OS instance) with
its own registry, user profile and processes. No host personal profile, credentials,
private music, live services, or writable host application directories. An existing
approved VM may be used; this plan does not authorize enabling Windows features,
creating accounts/signing credentials, changing security settings, or configuring
new virtualization on the user's machine.

In that environment, use a verified old 0.4.5 baseline and synthetic data. Record
its install location, registry identity, links and state hashes. Upgrade with a
new-version candidate preserving the real appId/executable identity; verify the
same installation is upgraded, Windows Plaza links replace old links correctly,
no duplicate uninstall registration remains, and character/pins/settings/notes
and synthetic resources persist after clean launch. Check uninstall preservation
and snapshot restoration there. Manual installer testing does not require a new
signing credential. Signed updater acceptance remains a separate authorized gate.

The current PC can safely support non-UI package extraction, hash/PE/manifest
inspection and synthetic unit fixtures. The ZIP's contents can support a later
isolated runtime preview when the parent grants GUI, without invoking NSIS.

## Distinct next preview version, only if release is authorized

Proposed next version: `0.4.6`, with tag `windows-v0.4.6` and artifacts
`Plaza-Windows-0.4.6-Setup-x64.exe`, `Plaza-Windows-0.4.6-x64.zip`, and the existing
source-archive convention. Local fetched tags currently end at windows-v0.4.5;
recheck remote releases/tags immediately before reserving a version, because this
is not a remote reservation or a guarantee that 0.4.6 remains available.

At that later point: update Windows/package.json version, rebuild from the reviewed
commit with locked tooling, rerun package/upgrade acceptance, generate fresh
checksums and candidate metadata tied to that version, and use only the existing
authorized signing/publication workflow if separately approved. Preserve appId,
package name, Plaza.exe, Mac branding/feed, and preview feed validation. Never
rename the current 0.4.5 binaries to 0.4.6; their embedded version must match.

No version bump, tag, push, release, signing setup, installer execution or host
registry/settings change was performed for this review. Audible speaker output,
DPI/layout acceptance and native Mac comparison remain pending.
