import Foundation
import CryptoKit
import Security
import PlazaCore

/// Account/origin-scoped encrypted state, separate from portable plaza files.
struct LocalSocialStore {
    let directory: URL
    private let keyProvider: ((String, Bool) throws -> SymmetricKey)?
    init(directory: URL? = nil, keyProvider: ((String, Bool) throws -> SymmetricKey)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mac Plaza/Sharing", isDirectory: true)
        self.keyProvider = keyProvider
    }
    static func scope(endpoint: URL, accountID: String) -> String {
        SHA256.hash(data: Data((endpoint.absoluteString + "|" + accountID).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func key(_ scope: String, create: Bool) throws -> SymmetricKey {
        if let keyProvider { return try keyProvider(scope, create) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.macplaza.sharing-key", kSecAttrAccount as String: scope]
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, create else { throw PlazaError.invalid("Unlock Keychain to read your saved discussions.") }
        let key = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw PlazaError.invalid("Could not protect the local sharing queue.") }
        return key
    }
    func load(endpoint: URL, accountID: String) throws -> LocalSocialState {
        let scope = Self.scope(endpoint: endpoint, accountID: accountID)
        let file = directory.appendingPathComponent(scope + ".sealed")
        guard FileManager.default.fileExists(atPath: file.path) else { return LocalSocialState(accountID: accountID) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 8_000_000 else { throw PlazaError.invalid("Saved discussions exceed their storage limit.") }
        let encrypted = try Data(contentsOf: file)
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key(scope, create: false), authenticating: Data(scope.utf8))
        var state = try JSONDecoder().decode(LocalSocialState.self, from: data).validated()
        guard state.accountID == accountID else { throw PlazaError.invalid("Saved discussions belong to a different account.") }
        state.prune(); return state
    }
    func save(_ state: LocalSocialState, endpoint: URL) throws {
        let state = try state.validated(), scope = Self.scope(endpoint: endpoint, accountID: state.accountID)
        let data = try JSONEncoder().encode(state)
        guard data.count <= 7_900_000 else { throw PlazaError.invalid("The local sharing cache is full.") }
        let encrypted = try AES.GCM.seal(data, using: key(scope, create: true), authenticating: Data(scope.utf8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(scope + ".sealed")
        try encrypted.combined!.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func remove(endpoint: URL, accountID: String) {
        let scope = Self.scope(endpoint: endpoint, accountID: accountID)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(scope + ".sealed"))
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.macplaza.sharing-key",
                       kSecAttrAccount as String: scope] as CFDictionary)
    }
}
