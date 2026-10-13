# Plaza for Windows 0.1.0

A Windows desktop preview that shares notes, drawings, replies and likes with Mac Plaza 0.16 or later through the existing Plaza service. Windows 10/11, x64. It has its own animated procedural plaza and character editor; the native Mac app remains available.

Install the Setup EXE, or extract the entire portable ZIP and run Plaza.exe. No Node, Python, Discord SDK or GitHub account is needed by users. The unsigned preview may show Windows SmartScreen publisher warnings. Download only from this repository or https://plaza.squidproductions.org.

1. Open Settings and Connect Discord. Approve in your browser and return to Plaza.
2. Open Friends, create an invitation, and give the code to your Mac or Windows friend. Alternatively enter their invitation. The receiving friend accepts the request.
3. On Mac, invitation controls are under Discord & Friends → Optional shared Mii profiles & Plaza invitations.
4. Write a note with Public · Plaza friends selected. Both platforms receive it on the next refresh (normally 15 seconds). Private notes and drafts stay on this computer. Drawings need a written description. Optional Steam App IDs identify the same game on either platform.

Notes are saved before sending; offline changes retry when the service reconnects. Use the same service address on both computers. Signing in again restores your server notes before uploading changes. Each Discord account has separate private data. Session credentials use Electron safeStorage (Windows DPAPI). Closing the window exits the app. Check Downloads & updates for new releases; this preview does not install updates automatically.

This is the first Windows companion, not feature parity with the native Mac app. It supports Plaza invitations rather than automatic Discord SDK friend discovery, appearance JSON rather than console Mii binary files, and procedural characters rather than imported Nintendo FFL/body resources. Desktop wallpaper integration, installed-app launching, native Discord presence, original crowd controllers and local recording imports remain Mac features. Original character appearance fields are preserved when importing Mac character JSON and sending notes.

## Build and test

Use Node 22+, pnpm 11.25.0 and Python 3.11+. From Windows/:

```sh
pnpm install --frozen-lockfile --ignore-scripts --config.block-exotic-subdeps=false
node node_modules/electron/install.js
pnpm test
pnpm test:desktop
pnpm dist
```

The official Electron rebuild dependency uses Electron's git-hosted node-gyp; the explicit pnpm setting permits that locked dependency. Install scripts are disabled; only Electron's binary installation is invoked. The Windows GitHub Actions job runs the tests on Windows, builds both downloads, and repeats desktop integration tests against the packaged EXE before publication. Python runs an isolated in-memory test service and is never bundled or required at runtime. Tests do not sign in to real Discord accounts, use production data, or send anything to the live service.

Original code is MIT licensed. Bundled Three.js r146 is MIT licensed; its complete notice is in src/vendor/THREE-LICENSE.txt. Electron includes its Chromium/Node/third-party license notices in the installed distribution. This Windows app does not bundle the AGPL FFL renderer, Discord SDK, Nintendo assets, recordings, credentials or the hosting database.
