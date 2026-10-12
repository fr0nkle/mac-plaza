import Foundation

/// Demo runs can select a fresh local sandbox without inheriting earlier QA
/// sessions. A directory override is ignored unless --demo is also present.
enum PlazaDataLocation {
    static var root: URL {
        directory(arguments: CommandLine.arguments,
                  support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                  temporary: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }

    static func directory(arguments: [String], support: URL, temporary: URL) -> URL {
        guard arguments.contains("--demo") else { return support.appendingPathComponent("MacPlaza") }
        if let argument = arguments.first(where: { $0.hasPrefix("--demo-directory=") }) {
            let path = String(argument.dropFirst("--demo-directory=".count))
            if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL }
        }
        return temporary.appendingPathComponent("MacPlaza-Demo")
    }
}
