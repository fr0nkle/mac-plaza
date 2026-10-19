// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlazaEngine", products: [.executable(name: "PlazaEngine", targets: ["PlazaEngine"])], targets: [
    .target(name: "PlazaCore", path: "Sources/PlazaCore"),
    .executableTarget(name: "PlazaEngine", dependencies: ["PlazaCore"])
], swiftLanguageModes: [.v5])
