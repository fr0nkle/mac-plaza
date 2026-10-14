# Plaza for Windows 0.2.0

Windows 10/11 x64. Install the Setup EXE, or extract the entire portable ZIP and run Plaza.exe. Users do not need Swift, Node, Python, or a GitHub account.

The Windows app follows the Mac plaza layout and uses its shared Swift crowd engine, original character artwork, Mii feature catalogs, local FFL renderer and imported body animations. It includes the eight-category Mii Maker, saved Miis, binary Mii/JSON/portrait export, installed apps and Steam shortcuts, recent-app rotation, app paging and layout undo, Steam store previews, square drawings and PNG export, notes/replies/likes, music previews and local imports and portable plazas.

## Wallpaper and Discord

Choose **Use as Wallpaper** in Preferences. Plaza attaches to the Windows Explorer desktop. Press **Escape** or choose **Return to Desktop** for passive wallpaper. Use the Plaza system tray icon to interact again, open Mii Maker/Friends/Preferences in companion windows, return to a regular window, or quit. Closing the main Windows window keeps Plaza in the system tray. Wallpaper pauses under large foreground windows; music yields to other audio and capture sessions. Lock and sleep pause the scene. Login and wallpaper-at-login are independent preferences.

Connect Discord in Preferences and authorize in your browser. The official Discord Social SDK discovers friends and availability automatically. Existing 0.1 sessions must disconnect and reconnect once to grant friend discovery. Shared Miis use the friend's chosen appearance; other Discord friends receive temporary local Miis or an appearance you assign on this computer. Profile sharing and app activity are optional. Custom statuses and games also need the existing service's shared-server integration. Explicit Plaza invitations remain available.

Use the same Plaza service address on both computers. Public notes, drawings, replies and likes work across Mac and Windows. Drawings need a description; a Steam App ID matches the same game on either platform. Private notes and drafts stay local. Pending changes save before sending and retry when the service returns. Each Discord account has separate private data. Credentials use Windows DPAPI through Electron safeStorage.

Import the same local FFLResHigh.dat and Men2.pack resources as on Mac for original rendering. Resources and recordings stay on this computer and are excluded from portable exports. Portable plazas exchange Miis, local notes and settings with Mac; reconnect platform-specific app shortcuts after importing. The app keeps a last saved backup and preserves unreadable files for recovery.

Windows uses Explorer, a tray icon and Windows app shortcuts in place of macOS desktop APIs, its menu bar and .app bundles. OS fonts, title bars, system dialogs and notifications follow Windows. Download updates from the website. This preview is unsigned and may show SmartScreen's publisher warning.

## Build and test

Use Node 22+, pnpm 11.25.0, Python 3.11+, Swift 6.4.1 for Windows and the Visual C++ build tools. Obtain Discord Social SDK 1.10.19337 directly from Discord and place its Windows x64 include/lib/bin release directories and notices in native/sdk/. The publishing workflow retrieves the same pinned, checksummed SDK from an unpublished repository build-input draft; standalone SDK files are excluded from source releases.

```sh
pnpm install --frozen-lockfile --ignore-scripts --config.block-exotic-subdeps=false
node node_modules/electron/install.js
pnpm build:native
pnpm build:engine
pnpm test
pnpm test:desktop
pnpm test:parity
pnpm dist
```

Copy the built native addon and Discord runtime dependencies into native/runtime/ before source launch. scripts/prepare-native.ps1 automates this for the publishing workflow. build:engine copies the matching Swift runtime for installed users. The shared preparation scripts read the adjacent Mac source tree, so build from the complete corresponding-source archive or repository.

CI tests source and packaged Windows executables, desktop attachment/restoration, passive input, companion windows, SDK loading, Mii editing, binary round trips, audio roles and two-way journal behavior against an isolated real service. Friend-roster tests cover identity validation, shared/local appearance precedence, stale activity and recipient filtering. Automated CI does not authorize a real Discord account. Optional PLAZA_FFL_RESOURCE and PLAZA_BODY_RESOURCE paths enable local imported-resource rendering tests without uploading those files.

Original project code is MIT licensed. The combined FFL renderer distribution includes AGPL-3.0-only code; corresponding source and licenses are included in the release source archive and src/ffl/vendor/. Preserve all component notices; see LICENSING.md. The official Discord runtime is a separately vendor-licensed dependency with its notices. Swift/Foundation/ICU/dispatch notices accompany native/runtime. Electron includes Chromium/Node notices. Console resources, Nintendo recordings, credentials and service databases are excluded.
