# Windows Plaza local candidate validation

This change fixes missing app islands and generic shortcut artwork in the Windows
port, and changes Windows-facing branding to Windows Plaza. Mac sources and
branding are unchanged.

## Verified fixes

The shared Swift engine serializes UUIDs in uppercase. Windows discovery creates
lowercase strings. The renderer's strict comparison dropped every selected app;
case-insensitive UUID matching now retains the original catalog entry and launch
path. A regression failed with 0 tiles before the fix and passes with 12 after it.

Windows shell icon lookup now uses the resolved executable when available, while
launching retains the original shortcut (including its arguments). Existing
custom/cached icons are preserved. Games without cached artwork retain letter
fallbacks.

On Windows, the isolated preview displayed 12 islands over the animated fallback
Mii scene, showed Windows Plaza in title/menu/header, opened Character Map from
both the list and a tile, and retained its synthetic character, pin and launch
history through a clean restart. Real executable artwork appeared after the icon
fix. Native Mac comparison and full DPI/layout acceptance are still pending;
edge labels and top-right control overlap warrant further review.

## Audio evidence and limits

The native monitor reported otherAudio=true and the mixer yielded as designed.
When otherAudio=false and covered=false, playback resumed. Existing local plaza
and settings M4A files were read in place using only path references in a synthetic
profile: plaza playhead advanced beyond 85 seconds at gain 0.12, and Settings
switched to its recording at gain 0.10 with the plaza voice paused.

No speaker output was heard or recorded by the test. Do not call audible output
verified. All seven roles, alternate theme selection, crossfades, preserved plaza
playhead, environment mute/resume, list behavior and companion delegation pass
Node VM fixtures with fake Audio/WebAudio. These fixtures do not decode audio or
validate the remaining roles on the physical device. No music files were bundled,
copied into tracked source or uploaded.

## Upgrade identity

- Keep package name `plaza-windows`: Electron's existing data-directory identity.
- Keep app ID `org.squidproductions.plaza.windows`: NSIS derives its UUID v5 from it.
- Keep executable `Plaza.exe`, original release artifact names, preview feed,
  pinned public key and signature validation.
- Change product/shortcut labels to `Windows Plaza`.
- Keep `deleteAppDataOnUninstall=false`.

Reviewed electron-builder 26.15.3: NSIS reads existing InstallLocation through the
app GUID and records/renames desktop and Start Menu ShortcutName. The update worker
passes the current install directory explicitly using /D. This is static evidence,
not an installed upgrade test. A fresh installation's default directory may use
Windows Plaza; existing installations should reuse their recorded path.

Version remains 0.4.5 deliberately. This is a local candidate, not a new published
release; the updater rejects same-version updates. Select a new version and test
an isolated old-to-new upgrade before any release or real installation.

## Build provenance

Pinned pnpm 11.25.0, Electron 44.7.0 and electron-builder 26.15.3; frozen lockfile,
initial lifecycle scripts disabled; official Electron installation script run
explicitly. packageManager now records the already documented pnpm version so
Corepack/build subprocesses do not fall back to another version.

Renderer assets regenerated from the adjacent verified Mac source. Native runtime
reused from the installed 0.4.5 preview: PlazaEngine.exe SHA256
39E57F78140C55216E7C94AF8F628A9A123008524AB665007BDD6F085BB49702.
Swift/Discord C++ inputs were not rebuilt. No credentials/signing keys created;
local packaging uses CSC_IDENTITY_AUTO_DISCOVERY=false and --publish never.
Packaged main/renderer/apps/music checked against source; test instrumentation,
synthetic profile overrides and private Audio directory are absent.

65/65 Node tests pass on Windows, including the temporary junction safety fixture.
Shipping Swift runtime tests pass. Syntax and diff checks pass.

Remaining gates: candidate installer execution/upgrade/shortcut migration,
physical sound output, remaining native music roles, private resource-pack/GPU,
DPI/accessibility/multimonitor, and authorized native Mac comparison. No full
parity certification, publishing or real installation is implied.

## Music correction — 2026-10-26

User correction: music should pause only when other music actually plays. The prior
observation `otherAudio=true` does not establish that other music was playing.

Confirmed defects in the old code: `native/plaza_native.cpp` classified any active
external capture session as other audio and classified arbitrary render peaks as
other audio. `src/main.cjs` also muted on covered/hidden windows. These are sufficient
false-positive paths; the recorded earlier boolean does not identify which path
caused the user's specific idle-desktop interruption.

The new policy requires a Windows media session declaring Playing and Music, plus
active, unmuted, nonzero render output matched by app identity or process filename.
It requires 1.5 seconds of sustained evidence, excludes Plaza/duplicate Plaza, and
resumes when evidence stops. Microphones and system-sound sessions are excluded.
No metadata, raw audio or playback controls are used. Window coverage/visibility no
longer automatically mutes music. Lock/suspend and explicit existing user settings
remain respected; manual music-off persists across interruption/resumption.

`PlazaMusicProbe.exe` is a separate read-only native helper with an owner-lifetime
handle, utility-process watchdog, bounded output and fail-open handling. Missing,
blocked, stale or unavailable observations leave music playing. Windows cannot
reliably classify arbitrary audio: players lacking Music playback type or a matching
render identity will not trigger automatic yielding. This conservative limitation
is intentional and needs live player compatibility checks.

Validation: 72/72 Node tests passed, including new idle/capture/notification,
paused/stopped/silent/muted/unknown-type, own/duplicate Plaza, positive matched music,
onset/stop/resume, helper-denial and manual-preference fixtures. The native helper
compiled x64 with MSVC 14.50.35717 and workspace-only official Microsoft Windows SDK
NuGet 10.0.26100.9169 headers/libs. Neither the SDK nor an OS setting was installed.

BLOCKED: a single hidden `PlazaMusicProbe.exe --once` read-only launch was rejected
by Windows with "An Application Control policy has blocked this file." It did not
execute. No launcher retry, unblock, policy change, signing setup or bypass was
attempted. Earlier PowerShell probe prototype was also blocked by script policy;
that prototype was discarded. Native media/audio runtime acceptance is unverified.
Further actual playback testing needs an authorized environment that allows this
build, without relaxing this PC's security policy. This is an OS policy block, not
a pending Codex approval ID. No desktop was used during this correction.

The earlier 0.4.5 local installer/ZIP does NOT include this correction. Do not
publish or overwrite it. No new release version was reserved; next preview remains
a later decision. Installer upgrade tests still require a disposable VM because
NSIS shares installed app identity, registry/uninstaller and Plaza.exe process name.
Actual speaker output, live other-player interruption, DPI/layout and native Mac
comparison remain pending. Installed app/profile and private recordings unchanged.

Compiled helper SHA-256 (latest local rebuild):
`7a40e3b137da4b1761d9d1601bae77939c2bd788cb0008947e1f9568e0d5ee42`.
This artifact is build evidence only; the blocked launch was the preceding binary
from the same source. No launch was attempted after rebuilding through the saved
build script. This does not establish that the helper runs on this host.
