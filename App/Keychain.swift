import Foundation
import Security
import UIKit

/// Секреты (ссылки подписок, сессия) храним в Keychain, а не в UserDefaults.
enum Keychain {
    private static let service = "com.litenergy.vpn"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Данные устройства для сервера подписок (лимит устройств в панели).
enum Device {
    /// Постоянный идентификатор установки: хранится в Keychain и переживает переустановку.
    static var hwid: String {
        if let saved = Keychain.get("hwid"), !saved.isEmpty { return saved }
        let id = UUID().uuidString.lowercased()
        Keychain.set("hwid", id)
        return id
    }

    static var model: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }

    static var osVersion: String { UIDevice.current.systemVersion }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// User-Agent начинается с «SFI» — так сервер подписок отдаёт готовую конфигурацию для нашего ядра.
    static var userAgent: String {
        "SFI/1.14.3 (LitEnergyVPN \(appVersion); iOS \(osVersion))"
    }
}
