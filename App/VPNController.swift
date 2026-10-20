import Foundation
import NetworkExtension

/// Управление VPN-туннелем через NETunnelProviderManager.
/// Конфиг передаётся в расширение напрямую (options + providerConfiguration) — App Group не нужен,
/// поэтому приложение продолжает работать после переподписи другим сертификатом.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var connectedDate: Date?
    @Published var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        Task { await load() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isConnected: Bool { status == .connected }
    var isBusy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }

    func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first
        update()
    }

    private func update() {
        status = manager?.connection.status ?? .disconnected
        connectedDate = manager?.connection.connectedDate
    }

    /// Bundle ID расширения ищем в самом приложении: после переподписи он может измениться.
    static var extensionBundleId: String {
        if let url = VPNDiagnostics.extensionURL(), let id = Bundle(url: url)?.bundleIdentifier {
            return id
        }
        return (Bundle.main.bundleIdentifier ?? "com.litenergy.vpn") + ".tunnel"
    }

    func connect(config: String) async {
        lastError = nil
        if VPNDiagnostics.extensionURL() == nil {
            lastError = VPNDiagnostics.current().problem
            return
        }
        do {
            let manager = self.manager ?? NETunnelProviderManager()
            let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.extensionBundleId
            proto.serverAddress = "LitEnergy VPN"
            proto.providerConfiguration = ["configContent": config]
            proto.disconnectOnSleep = false
            manager.protocolConfiguration = proto
            manager.localizedDescription = "LitEnergy VPN"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            self.manager = manager
            try manager.connection.startVPNTunnel(options: ["configContent": config as NSString])
            update()
        } catch {
            lastError = VPNDiagnostics.explain(error)
            update()
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    /// Новая конфигурация (сменили сервер или настройки): работающий туннель перезагружается без отключения.
    func update(config: String) async {
        guard let manager, let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        proto.providerConfiguration = ["configContent": config]
        manager.protocolConfiguration = proto
        try? await manager.saveToPreferences()
        guard isConnected, let session = manager.connection as? NETunnelProviderSession, let data = config.data(using: .utf8) else { return }
        do {
            try session.sendProviderMessage(data) { [weak self] reply in
                guard let reply, let text = String(data: reply, encoding: .utf8), !text.isEmpty else { return }
                Task { @MainActor in self?.lastError = text }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}


/// Проверка подписи: почему iOS не даёт добавить VPN.
struct VPNDiagnostics {
    enum Check {
        case yes, no, unknown
    }

    let extensionFound: Bool
    let appEntitlement: Check
    let extensionEntitlement: Check
    let teamName: String

    static func current() -> VPNDiagnostics {
        let appex = extensionURL()
        let appProfile = profile(in: Bundle.main.bundleURL)
        let extProfile = appex.flatMap { profile(in: $0) }
        return VPNDiagnostics(
            extensionFound: appex != nil,
            appEntitlement: check(appProfile),
            extensionEntitlement: appex == nil ? .no : check(extProfile),
            teamName: (appProfile?["TeamName"] as? String) ?? ""
        )
    }

    var problem: String? {
        if !extensionFound {
            return "В установленном приложении нет VPN-модуля. При подписи не удаляйте расширения (PlugIns/PacketTunnel.appex) — подписывайте IPA целиком."
        }
        if appEntitlement == .no || extensionEntitlement == .no {
            return "Сертификат подписи не поддерживает VPN: в профиле нет разрешения Network Extensions (Packet Tunnel). Переподпишите приложение сертификатом с этим разрешением."
        }
        return nil
    }

    static func explain(_ error: Error) -> String {
        let ns = error as NSError
        let diag = current()
        if let problem = diag.problem {
            return problem
        }
        if ns.domain == NEVPNErrorDomain, ns.code == NEVPNError.configurationReadWriteFailed.rawValue {
            return "iOS не разрешил добавить VPN (\(ns.localizedDescription)). Нажмите «Подключить» ещё раз и выберите «Разрешить». Если окно не появляется — сертификат подписи не поддерживает VPN (Network Extensions)."
        }
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }

    static func extensionURL() -> URL? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        else { return nil }
        for item in items where item.pathExtension == "appex" {
            if let bundle = Bundle(url: item),
               let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String,
               point == "com.apple.networkextension.packet-tunnel"
            {
                return item
            }
        }
        return nil
    }

    /// Содержимое embedded.mobileprovision (CMS-контейнер, внутри обычный plist).
    static func profile(in bundleURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("embedded.mobileprovision")),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound ..< end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
    }

    static func check(_ profile: [String: Any]?) -> Check {
        guard let profile else { return .unknown } // нет профиля: TrollStore/джейлбрейк — проверить нельзя
        let ent = profile["Entitlements"] as? [String: Any] ?? [:]
        let ne = ent["com.apple.developer.networking.networkextension"] as? [String] ?? []
        return ne.contains("packet-tunnel-provider") ? .yes : .no
    }

    var report: String {
        func s(_ c: Check) -> String {
            switch c {
            case .yes: return "есть"
            case .no: return "нет"
            case .unknown: return "не удалось проверить"
            }
        }
        var lines = [
            "VPN-модуль в приложении: \(extensionFound ? "есть" : "нет")",
            "Разрешение VPN у приложения: \(s(appEntitlement))",
            "Разрешение VPN у модуля: \(s(extensionEntitlement))",
        ]
        if !teamName.isEmpty { lines.append("Подпись: \(teamName)") }
        lines.append(problem ?? "Подпись в порядке.")
        return lines.joined(separator: "\n")
    }
}
