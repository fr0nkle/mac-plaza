# Building and validating the local port

## Scope and prerequisites

Build from the complete repository: preparation reads the adjacent Mac sources.
Use package.json/pnpm-lock.yaml (Electron 44.7.0), Node 22+, pnpm 11.25.0 and
Swift 6. The inherited Windows workflow pins Swift 6.4.1. Local checks used
Apple Swift 6.3.3 and the already installed Node 24.21.0 on arm64 macOS.
Python's standard library is enough for the HTTP fixture; the full backend suite
also needs Server/requirements.txt (`discord.py`).

No Windows VM, Wine, MSVC or Windows Swift SDK was available during this task.
Windows builds require Windows 10/11 x64, Visual C++ build tools, Windows SDK and
Swift. Mac compilation is useful shared-code evidence only.

## Dependencies and shared engine

From Windows/:

```sh
pnpm install --frozen-lockfile --ignore-scripts --config.block-exotic-subdeps=false
node node_modules/electron/install.js
pnpm build:engine
pnpm test
pnpm test:shared
pnpm test:runtime
pnpm test:contracts
```

`build:engine` prepares the same Mac PlazaCore/FFL/artwork and builds the Swift
subprocess into native/runtime. Compiler module caches stay in Engine/.build.
`test:shared` copies and runs the shipping PlazaCore tests without requiring the
Mac executable, AppKit, Discord's Mac framework or Sparkle.
`test:contracts` starts the unchanged backend on an ephemeral 127.0.0.1 port with
an in-memory database and synthetic sessions. It exchanges actual Swift
publishing/decoding models and Windows payloads through the production transport.
It never uses a real Discord account. Set `PYTHON=python` in PowerShell if needed.

For the full backend tests, use an isolated virtualenv:

```sh
python3 -m venv ../.venv-port
../.venv-port/bin/python -m pip install -r ../Server/requirements.txt
../.venv-port/bin/python -B -m unittest discover -s ../Server
```

On Windows the interpreter is `..\.venv-port\Scripts\python.exe`.
Do not copy the production service database or .env into this tree.

## Windows native bridge

Obtain the official Discord Social SDK **1.10.19337** through the project's
existing licensed access. Supply Windows x64 `include/`, `lib/release/`,
`bin/release/` and `License-Notices.txt` beneath native/sdk/. Do not substitute
unofficial binaries or publish the vendor archive.

The original project already has an unpacked Windows SDK. A local copy is staged
in this isolated tree's ignored native/sdk/ for review; its Discord DLL is x64.
The vendor archive was absent, so its archive checksum was not reverified. Keep
this dependency private; do not add it to Git.

For matching local audio, stage the existing Mac recordings explicitly:

```sh
python scripts/prepare-music.py --source "/path/to/Mac Resources/Audio"
```

This copies all seven soundtrack roles and click/back effects into the ignored
native/runtime/Audio folder and records hashes. It never downloads. This task
used the existing local project recordings. A source-only clone retains generated
ambience and user-import controls when recordings are absent; including these
recordings in any future distribution needs separate review.

In a Visual Studio developer PowerShell, from Windows/:

```powershell
pnpm build:native
New-Item -ItemType Directory -Force native/runtime | Out-Null
Copy-Item build/Release/plaza_native.node native/runtime/
Copy-Item native/sdk/bin/release/* native/runtime/ -Exclude arm64 -Force
Copy-Item native/sdk/License-Notices.txt native/runtime/DISCORD-LICENSE-NOTICES.txt
pnpm build:engine
```

The inherited prepare-native.ps1 can also retrieve a checksummed SDK from a
private repository build-input draft, with existing access. It was not run in
this task. No signing credentials are needed for local tests.

## Run with separate local data

Windows, from Windows/:

```powershell
node_modules/.bin/electron . --user-data-dir="$env:TEMP\mii-plaza-port-review"
```

Mac development UI preview (Windows OS integration is unavailable):

```sh
node_modules/.bin/electron . --user-data-dir=/tmp/mii-plaza-port-review
```

Fresh profiles run offline. Do not connect personal Discord accounts for fixture
tests. Open Mii Maker, write a Private post, and open Miiverse to inspect its
independent window. Do not use normal app data. Test scripts create and remove
their own temporary profiles.

```sh
pnpm test:parity
pnpm test:desktop
pnpm test:features
pnpm test:window
pnpm test:current
pnpm test:library
pnpm test:recovery
pnpm test:notifications
pnpm test:list
```

Windows also exercises native paths where platform guards allow. Optional
PLAZA_FFL_RESOURCE and PLAZA_BODY_RESOURCE point to locally owned FFL and converted
body fixtures; never upload those files. Fallback rendering and generated ambience
require no console resources or bundled recording. `test:pack` accepts an optional
PLAZA_RESOURCE_PACK pointing to a privately owned .plazapack; it verifies actual
heads/bodies, all 172 animations, six audio files, backup and preserved Miis in a
temporary profile. No resource/music is copied into tracked source.

Run GUI suites sequentially to avoid competing for focus and audio. `test:runtime`
exercises the actual Swift game-history and independent stationary-post clock.
`test:recovery` uses semantically invalid saves, restores a valid backup, and
checks safe/reduced-motion mode and update UI state; signature validation is in
unit tests. `test:notifications` uses only the synthetic loopback service and checks
quiet history, read-all delivery, privacy-safe alerts, exact-post routing, reply
focus and cross-window account isolation.

After Windows tests pass, local packaging is:

```powershell
$env:CSC_IDENTITY_AUTO_DISCOVERY='false'
pnpm dist
```

This uses `--publish never` for local builds. The Windows preview workflow validates
shared core/protocols on pushes to the windows branch. An explicitly pushed
windows-v<version> tag additionally compiles the Windows native bridge, packages an
unsigned installer/portable ZIP, verifies runtime/source/checksums, and publishes
an UNTESTED GitHub prerelease. It leaves the Mac release and signed updater feed
unchanged. The standalone SDK stays in an unpublished build-input draft. Native app, installer/updater and
two-device acceptance remain separate gates in PORT-PLAN.md.


## Preview update delivery

Preview builds use the dedicated signed windows-preview-update.json feed and
require channel preview. Mac updates and the legacy Windows stable URL are
untouched. See RELEASE-PROCESS.md: an explicit tag builds/tests/publishes preview
artifacts; the existing signing Mac then verifies them, signs metadata locally and
publishes the Site. No signing key is uploaded to CI. The Windows workflow also
exercises a disposable installed older baseline with ephemeral test signatures,
manual and automatic replacement, relaunch and saved data/resource preservation.
Those fixtures are excluded from public release artifacts.
