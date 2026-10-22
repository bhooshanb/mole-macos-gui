import Foundation
import Security
import Combine

enum SparkCleanLicenseError: LocalizedError {
    case required
    case verificationFailed(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .required:
            return "Activate a valid SparkClean license to run this feature."
        case .verificationFailed(let message):
            return "Could not verify the SparkClean license: \(message)"
        case .storage(let message):
            return message
        }
    }
}

@MainActor
final class SparkCleanLicenseManager: ObservableObject {
    static let shared = SparkCleanLicenseManager()

    // The Dodo API secret remains on the server; the app only calls these
    // license endpoints over HTTPS.
    private let apiBaseURL = URL(string: "https://apps.silverstonelabs.in")!

    /// Where users buy a one-time license key (Dodo Payments storefront).
    static let purchaseURL = URL(string: "https://apps.silverstonelabs.in/")!
    private let keychainService = "fun.sparkclean.app.license"
    private let keychainAccount = "dodo-license-key"
    private let instanceKeychainAccount = "dodo-license-instance-id"
    private let legacyInstanceDefaultsKey = "dodoLicenseKeyInstanceId"

    @Published private(set) var isActivated = false
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private(set) var messageIsSuccess = false
    @Published private(set) var lastChecked: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate the activation ID from UserDefaults so Reset Preferences
        // cannot orphan a key that remains safely stored in Keychain.
        var instanceId = Self.readKey(
            service: keychainService,
            account: instanceKeychainAccount
        )
        if instanceId == nil,
           let legacyId = defaults.string(forKey: legacyInstanceDefaultsKey),
           !legacyId.isEmpty {
            try? Self.storeKey(
                legacyId,
                service: keychainService,
                account: instanceKeychainAccount
            )
            instanceId = Self.readKey(
                service: keychainService,
                account: instanceKeychainAccount
            )
            if instanceId != nil {
                defaults.removeObject(forKey: legacyInstanceDefaultsKey)
            }
        }

        let licenseKey = Self.readKey(service: keychainService, account: keychainAccount)
        isActivated = licenseKey != nil && instanceId != nil
    }

    var hasStoredCredentials: Bool {
        Self.readKey(service: keychainService, account: keychainAccount) != nil &&
            Self.readKey(service: keychainService, account: instanceKeychainAccount) != nil
    }

    func activate(licenseKey rawKey: String) async {
        let licenseKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            setMessage("Enter the license key from your Dodo Payments email.")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let result: ActivationResponse = try await post(
                path: "/api/license/activate",
                body: ["licenseKey": licenseKey, "deviceName": Host.current().localizedName ?? "Mac"]
            )
            guard result.activated, !result.licenseKeyInstanceId.isEmpty else {
                setMessage("Dodo did not activate this license. Check the key and try again.")
                return
            }

            // Save both values in Keychain. Do not mark the license activated
            // unless both credentials are durable on this Mac.
            do {
                try Self.storeKey(licenseKey, service: keychainService, account: keychainAccount)
                try Self.storeKey(
                    result.licenseKeyInstanceId,
                    service: keychainService,
                    account: instanceKeychainAccount
                )
            } catch {
                // Never leave a mixed old/new credential pair in Keychain.
                clearStoredCredentials()
                throw error
            }
            defaults.removeObject(forKey: legacyInstanceDefaultsKey)
            isActivated = true
            lastChecked = Date()
            setMessage("SparkClean is activated on this Mac.", success: true)
        } catch {
            isActivated = hasStoredCredentials
            setMessage(error.localizedDescription)
        }
    }

    /// Refresh the Settings status when saved credentials exist. A missing
    /// license stays quiet until the user opens the License tab.
    func validateIfPresent() async {
        guard hasStoredCredentials else { return }
        await validate()
    }

    /// Contact Dodo and update the visible status. A network error preserves
    /// local activation for display, but GPL-covered app features remain usable without activation.
    /// This check only reports the status of an optional purchase.
    func validate() async {
        guard hasStoredCredentials else {
            isActivated = false
            setMessage("Enter your license key to activate SparkClean.")
            return
        }

        do {
            try await validateStoredLicense()
            setMessage("Your SparkClean license is valid.", success: true)
        } catch SparkCleanLicenseError.required {
            setMessage("Dodo no longer accepts this license. Contact support if you think this is a mistake.")
        } catch {
            setMessage(error.localizedDescription)
        }
    }

    /// A local Keychain entry is not proof of an active purchase. This manual
    /// status check does not gate GPL-covered app features.
    func validateStoredLicense() async throws {
        guard let licenseKey = Self.readKey(service: keychainService, account: keychainAccount),
              let instanceId = Self.readKey(service: keychainService, account: instanceKeychainAccount),
              !licenseKey.isEmpty, !instanceId.isEmpty else {
            isActivated = false
            throw SparkCleanLicenseError.required
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let result: ValidationResponse = try await post(
                path: "/api/license/validate",
                body: ["licenseKey": licenseKey, "licenseKeyInstanceId": instanceId]
            )
            guard result.valid else {
                clearStoredCredentials()
                isActivated = false
                lastChecked = Date()
                throw SparkCleanLicenseError.required
            }
            isActivated = true
            lastChecked = Date()
        } catch let error as SparkCleanLicenseError {
            throw error
        } catch {
            throw SparkCleanLicenseError.verificationFailed(error.localizedDescription)
        }
    }

    private func clearStoredCredentials() {
        try? Self.deleteKey(service: keychainService, account: keychainAccount)
        try? Self.deleteKey(service: keychainService, account: instanceKeychainAccount)
        defaults.removeObject(forKey: legacyInstanceDefaultsKey)
    }

    private func setMessage(_ value: String, success: Bool = false) {
        message = value
        messageIsSuccess = success
    }

    private func post<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: apiBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SparkCleanLicenseError.verificationFailed("The server returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw SparkCleanLicenseError.verificationFailed(
                payload?.error ?? "License service returned an error (\(http.statusCode))."
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct ActivationResponse: Decodable {
        let activated: Bool
        let licenseKeyInstanceId: String
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private static func readKey(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storeKey(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw SparkCleanLicenseError.storage("Could not save license data in Keychain.")
            }
        } else if status != errSecSuccess {
            throw SparkCleanLicenseError.storage("Could not save license data in Keychain.")
        }
    }

    private static func deleteKey(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SparkCleanLicenseError.storage("Could not remove license data from Keychain.")
        }
    }
}
