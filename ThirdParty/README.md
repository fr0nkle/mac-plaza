# Local FFL dependency sources

The application vendors FFL.js 2.2.2 (AGPL-3.0-only), the Wii U FFL decompilation port, the RIO headers it uses, ninTexUtils, and Three.js r144. Exact upstream commits are in VERSIONS.txt. Licenses and notices remain with each source tree and in the app's FFL/vendor directory. No Nintendo resource archives are included.

The application adapter is Sources/MacPlaza/Resources/FFL/plaza.js and Sources/MacPlaza/FFLRenderer.swift. It calls the actual FFL model builder and texture compositor, then uses upstream FFLShaderMaterial for Wii U head shading. Bodies and locomotion are Mac Plaza's own implementation.

## Rebuild the WebAssembly library

Activate Emscripten 4.0.10, install CMake, then run `zsh scripts/build-ffl.sh` from the project. Optionally set CMAKE_BIN to an absolute CMake executable. The ordinary app build uses the checked-in WebAssembly file and requires neither Emscripten nor Internet access.

The small changes to FFL's sources are:

- `wasmBinary` is included in INCOMING_MODULE_JS_API, allowing WebKit to initialize directly from local bytes with no fetch.
- `MacPlazaFFLHasGX2()` reports whether Wii U tiled texture conversion is compiled in. The application checks it during startup.
- `MacPlazaFFLVerifyGX2()` round-trips generated R8, RG8 and RGBA8 pixels through the actual GX2 tiler/deswizzler; startup checks its result.
- The probes are added to emscripten-exports.json.
- Dynamic execution is disabled and undefined-symbol errors are enabled.

FFL_NO_NINTEXUTILS must stay OFF. The Wii U resource uses GX2 tiled textures; supporting only Miitomo linear textures is insufficient. The build compiles gx2Surface.cpp and addrlib.cpp. The local build disables dynamic execution and builds without the upstream obsolete `$stackTrace` warning. Runtime initialization, native FFL capability, head rendering and expressions are tested in WebKit.

FFL.js's browser distributions and FFLShaderMaterial are unchanged upstream builds. Corresponding unbundled JS sources are in FFL.js/; Three.js sources are in three/. FFL.js can regenerate browser bundles using its rolldown configuration.

Private use stays local. Distribution of the combined application must follow the included AGPL and other component licenses and provide corresponding source, including these trees and the app adapter. The 0.4 source archive contains the local integration and dependency sources.

Mac Plaza 0.6 additionally compiles `ninTexUtils/src/ninTexUtils/bcn/decompress.c` and exposes `MacPlazaDecodeMenuBC3` to decode the original menu body atlas with its GX2 tile mode, swizzle and pitch. The native entry point checks input dimensions, size and expected calculated layout before deswizzling/decompression. The original SARC/Yaz0/BFRES reader and animation player are in `Sources/MacPlaza/Resources/FFL/menu-assets.js` and `original-body.js`; no external parser package is required. Model/animation data is imported by the user and is excluded from the corresponding-source bundle. Format field references were checked against KillzXGaming/BfresLibrary; no code from that repository is redistributed.

## Discord Social SDK

`DiscordSocialSDK/discord_social_sdk` contains the official macOS SDK **1.10.19337**, downloaded from the Discord Developer Portal after application enrollment. `include/` provides the C/C++ bridge headers; `lib/release/discord_partner_sdk.framework` includes the universal macOS runtime and its bundled dependencies. Preserve framework symlinks. `License-Notices.txt` ships in the app resources. Review Discord’s Social SDK terms before redistributing; this SDK is vendor licensed, not part of the project’s own license.

## Sparkle

Sparkle **2.10.0** is vendored from the official Sparkle release. Its framework is embedded in Mac Plaza; LICENSE ships in the app. The included official tools generate Keychain signing keys and sign private update archives. The update public key is in scripts/Info.plist; private keys are never in the repository.
