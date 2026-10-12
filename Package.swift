// swift-tools-version: 6.0
import PackageDescription
import Foundation

let discordRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("ThirdParty/DiscordSocialSDK/discord_social_sdk")
let discordFrameworks = discordRoot.appendingPathComponent("lib/release").path

let sparkleFrameworks = discordRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sparkle").path

let package = Package(
    name: "MacPlaza",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "MacPlaza", targets: ["MacPlaza"])],
    targets: [
        .target(name: "PlazaCore"),
        .target(name: "DiscordSocialBridge", cxxSettings: [.unsafeFlags(["-I" + discordRoot.appendingPathComponent("include").path])],
                linkerSettings: [.unsafeFlags(["-F" + discordFrameworks, "-framework", "discord_partner_sdk", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                                 .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", discordFrameworks], .when(configuration: .debug))]),
        .executableTarget(name: "MacPlaza", dependencies: ["PlazaCore", "DiscordSocialBridge"], resources: [.copy("Resources/FFL"), .copy("Resources/Audio")],
            swiftSettings: [.unsafeFlags(["-F" + sparkleFrameworks])],
            linkerSettings: [.unsafeFlags(["-F" + sparkleFrameworks, "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                             .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sparkleFrameworks], .when(configuration: .debug))]),
        .testTarget(name: "PlazaCoreTests", dependencies: ["PlazaCore"]),
        .testTarget(name: "MacPlazaTests", dependencies: ["MacPlaza", "PlazaCore"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
