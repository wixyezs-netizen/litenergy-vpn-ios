import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []
    @Published var currentId: String? { didSet { defaults.set(currentId, forKey: "current") } }
    @Published var settings = ConnectionSettings() { didSet { save(settings, "settings") } }
    @Published private(set) var selectedServers: [String: String] = [:] // id подписки → тег сервера / auto
    @Published private(set) var tariffs: [Tariff] = Tariff.fallback
    @Published private(set) var accountTitle: String?
    @Published var updating = false

    private let defaults = UserDefaults.standard
    let demo: Bool

    init() {
        demo = UserDefaults.standard.bool(forKey: "demo")
        subscriptions = load([Subscription].self, "subscriptions") ?? []
        settings = load(ConnectionSettings.self, "settings") ?? ConnectionSettings()
        selectedServers = load([String: String].self, "selected") ?? [:]
        tariffs = load([Tariff].self, "tariffs") ?? Tariff.fallback
        accountTitle = defaults.string(forKey: "account")
        currentId = defaults.string(forKey: "current")
        if demo { seedDemo() }
        if current == nil { currentId = subscriptions.first?.id }
    }

    var current: Subscription? { subscriptions.first { $0.id == currentId } }
    var session: String? { Keychain.get("session") }
    var isLoggedIn: Bool { session != nil }

    var selectedServer: String {
        guard let id = currentId else { return ConfigBuilder.autoTag }
        return selectedServers[id] ?? ConfigBuilder.autoTag
    }

    var selectedServerName: String {
        let tag = selectedServer
        if tag == ConfigBuilder.autoTag || !(current?.servers.contains { $0.tag == tag } ?? false) { return "Автовыбор" }
        return tag
    }

    func selectServer(_ tag: String) {
        guard let id = currentId else { return }
        selectedServers[id] = tag
        save(selectedServers, "selected")
    }

    // MARK: подписки

    /// Добавить по ссылке (буфер, QR, диплинк). Возвращает id.
    @discardableResult
    func importLink(_ raw: String) async throws -> String {
        guard let url = SubscriptionLoader.normalize(raw) else {
            throw LitError("Это не ссылка на подписку. Скопируйте ссылку из бота или личного кабинета.")
        }
        // та же ссылка уже добавлена — просто обновляем
        if let existing = subscriptions.first(where: { Keychain.get("sub." + $0.id) == url.absoluteString }) {
            currentId = existing.id
            try await refresh(existing.id)
            return existing.id
        }
        updating = true
        defer { updating = false }
        let loaded = try await SubscriptionLoader.fetch(url)
        let id = UUID().uuidString
        Keychain.set("sub." + id, url.absoluteString)
        try writeConfig(loaded.config, id: id)
        let name = loaded.info.title.isEmpty ? "LitEnergy VPN" : loaded.info.title
        subscriptions.append(Subscription(id: id, name: name, info: loaded.info, servers: loaded.servers, lastUpdated: Date()))
        persist()
        currentId = id
        return id
    }

    func refresh(_ id: String? = nil) async throws {
        guard let id = id ?? currentId, !demo else { return }
        guard let raw = Keychain.get("sub." + id), let url = URL(string: raw) else {
            throw LitError("Ссылка подписки не найдена. Добавьте подписку заново.")
        }
        updating = true
        defer { updating = false }
        let loaded = try await SubscriptionLoader.fetch(url)
        try writeConfig(loaded.config, id: id)
        if let i = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[i].info = loaded.info
            subscriptions[i].servers = loaded.servers
            if !loaded.info.title.isEmpty { subscriptions[i].name = loaded.info.title }
            subscriptions[i].lastUpdated = Date()
            persist()
        }
    }

    /// Пора обновить по интервалу из подписки.
    var needsRefresh: Bool {
        guard let sub = current else { return false }
        guard let last = sub.lastUpdated else { return true }
        return Date().timeIntervalSince(last) > sub.info.updateHours * 3600
    }

    func remove(_ id: String) {
        Keychain.set("sub." + id, nil)
        try? FileManager.default.removeItem(at: configURL(id))
        subscriptions.removeAll { $0.id == id }
        selectedServers[id] = nil
        save(selectedServers, "selected")
        persist()
        if currentId == id { currentId = subscriptions.first?.id }
    }

    /// Готовая конфигурация для туннеля.
    func tunnelConfig() throws -> String {
        guard let id = currentId else { throw LitError("Сначала добавьте подписку.") }
        guard let data = try? Data(contentsOf: configURL(id)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw LitError("Конфигурация не загружена. Обновите подписку.") }
        return try ConfigBuilder.build(json, selected: selectedServer, settings: settings)
    }

    var hasConfig: Bool {
        guard let id = currentId else { return false }
        return FileManager.default.fileExists(atPath: configURL(id).path)
    }

    /// Ссылка подписки для показа: только начало и конец.
    func maskedLink(_ id: String) -> String {
        guard let raw = Keychain.get("sub." + id), let url = URL(string: raw) else { return "" }
        let path = url.path
        let tail = path.count > 4 ? String(path.suffix(4)) : ""
        return "\(url.host ?? "")/…\(tail)"
    }

    // MARK: аккаунт

    func signIn(_ account: Api.Account) async throws {
        Keychain.set("session", account.token)
        accountTitle = account.title
        defaults.set(account.title, forKey: "account")
        var link = account.subscriptionURL
        if let boot = try? await Api.bootstrap(account.token) {
            if !boot.tariffs.isEmpty { setTariffs(boot.tariffs) }
            if link == nil || link?.isEmpty == true { link = boot.subscriptionURL }
        }
        guard let link, !link.isEmpty else {
            throw LitError("Вход выполнен, но активной подписки нет. Оформите её в боте или на сайте.")
        }
        try await importLink(link)
    }

    func signOut() {
        Keychain.set("session", nil)
        accountTitle = nil
        defaults.removeObject(forKey: "account")
    }

    /// Тарифы из кабинета (если вошли) и продление сессии.
    func loadAccount() async {
        guard let token = session, !demo else { return }
        if let boot = try? await Api.bootstrap(token), !boot.tariffs.isEmpty {
            setTariffs(boot.tariffs)
        }
        if let fresh = try? await Api.refreshSession(token), !fresh.isEmpty {
            Keychain.set("session", fresh)
        }
    }

    private func setTariffs(_ list: [Tariff]) {
        tariffs = list
        save(list, "tariffs")
    }

    // MARK: хранение

    private var configDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("subscriptions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func configURL(_ id: String) -> URL {
        configDir.appendingPathComponent(id + ".json")
    }

    private func writeConfig(_ config: [String: Any], id: String) throws {
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: configURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func persist() {
        if !demo { save(subscriptions, "subscriptions") }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: демо для скриншотов сборки

    private func seedDemo() {
        let expired = defaults.bool(forKey: "demo_expired")
        var info = SubscriptionInfo()
        info.download = 13_314_398_617
        info.upload = 1_020_000_000
        info.total = expired ? 0 : 107_374_182_400
        info.expire = Date().timeIntervalSince1970 + (expired ? -86400 : 28 * 86400)
        info.title = "LitEnergy VPN"
        let servers = [
            Server(tag: "🇩🇪 Германия · Игровой", type: "shadowsocks", host: "127.0.0.1", port: 1234),
            Server(tag: "🇫🇮 Финляндия · Игровой", type: "vless", host: "127.0.0.1", port: 8443),
            Server(tag: "🇫🇮 Финляндия · Видео", type: "shadowsocks", host: "127.0.0.1", port: 1234),
            Server(tag: "🇩🇪 Германия · Видео", type: "vless", host: "127.0.0.1", port: 8443),
        ]
        subscriptions = [Subscription(id: "demo", name: "LitEnergy VPN", info: info, servers: servers, lastUpdated: Date())]
        currentId = "demo"
    }
}
