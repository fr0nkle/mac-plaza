# Discord Social SDK build dependency

Download the macOS Social SDK from your Discord Developer Portal after enabling
Social SDK for your application and reviewing Discord's terms. The integration
currently targets SDK 1.10.19337. Extract its include directory and release
framework into `discord_social_sdk/` beside this file, preserving its layout.
See Server/README.md for the application's Discord setup.

The SDK is proprietary and is not covered by Mac Plaza's MIT license. Release
apps embed the framework as an integrated dependency under Discord's SDK terms.
Standalone SDK headers/binaries are excluded from new source distributions.

https://discord.com/developers/applications
https://support-dev.discord.com/hc/en-us/articles/30225844245271-Discord-Social-SDK-Terms
