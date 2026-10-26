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
