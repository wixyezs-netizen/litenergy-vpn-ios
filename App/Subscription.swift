import Foundation

// MARK: - Модель

struct SubscriptionInfo: Codable, Equatable {
    var upload: Int64 = 0
    var download: Int64 = 0
    var total: Int64 = 0 // 0 — безлимит
    var expire: Double = 0 // секунды Unix, 0 — бессрочно
    var title = ""
    var supportURL = ""
    var announce = ""
    var updateHours: Double = 12

    var used: Int64 { upload + download }
    var expireDate: Date? { expire > 0 ? Date(timeIntervalSince1970: expire) : nil }
    var isExpired: Bool { expire > 0 && expire < Date().timeIntervalSince1970 }
    var isTrafficOver: Bool { total > 0 && used >= total }

    var daysLeft: Int? {
        guard expire > 0 else { return nil }
        return max(0, Int(ceil((expire - Date().timeIntervalSince1970) / 86400)))
    }

    var trafficLine: String {
        if total > 0 {
            return "Трафик: \(ByteFormat.text(used)) из \(ByteFormat.text(total))"
        }
        return used > 0 ? "Трафик: \(ByteFormat.text(used)) · безлимит" : "Безлимитный трафик"
    }

    var expireLine: String {
        guard let date = expireDate else { return "Бессрочная подписка" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return (isExpired ? "Закончилась " : "До ") + f.string(from: date)
    }
}

struct Server: Codable, Hashable, Identifiable {
    var id: String { tag }
    let tag: String
    let type: String
    let host: String
    let port: Int

    var protocolName: String {
        switch type {
        case "vless": return "VLESS"
        case "vmess": return "VMess"
        case "trojan": return "Trojan"
        case "shadowsocks": return "Shadowsocks"
        case "hysteria2": return "Hysteria 2"
        case "tuic": return "TUIC"
        case "wireguard": return "WireGuard"
        default: return type.uppercased()
        }
    }

    /// UDP-протоколы: TCP-пинг до них не измерить.
    var isUDP: Bool { type == "hysteria2" || type == "tuic" || type == "wireguard" || type == "hysteria" }
}

struct Subscription: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var info: SubscriptionInfo
    var servers: [Server]
    var lastUpdated: Date?
}

enum ByteFormat {
    static func text(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824 { return String(format: "%.1f ГБ", b / 1_073_741_824).replacingOccurrences(of: ".", with: ",") }
        if b >= 1_048_576 { return String(format: "%.0f МБ", b / 1_048_576) }
        return String(format: "%.0f КБ", max(0, b / 1024))
    }
}

struct LitError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Загрузка подписки

enum SubscriptionLoader {
    struct Loaded {
        let info: SubscriptionInfo
        let config: [String: Any]
        let servers: [Server]
    }

    static let netError = "Сервер не отвечает. Проверьте интернет и попробуйте ещё раз."

    /// Ссылка из буфера, QR-кода или диплинка → URL подписки.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("litenergy://") {
            guard let comps = URLComponents(string: s),
                  let value = comps.queryItems?.first(where: { $0.name == "url" })?.value
            else { return nil }
            s = value
        }
        // ссылка может прийти внутри текста сообщения
        if !s.lowercased().hasPrefix("http"), let range = s.range(of: "https://[^\\s]+", options: .regularExpression) {
            s = String(s[range])
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    static func fetch(_ url: URL) async throws -> Loaded {
        var lastError: Error = LitError(netError)
        for attempt in 0 ..< 3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 900_000_000) }
            do {
                return try await fetchOnce(url)
            } catch let error as LitError {
                throw error
            } catch {
                lastError = LitError(netError)
            }
        }
        throw lastError
    }

    private static func fetchOnce(_ url: URL) async throws -> Loaded {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(Device.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Device.hwid, forHTTPHeaderField: "x-hwid")
        request.setValue("iOS", forHTTPHeaderField: "x-device-os")
        request.setValue(Device.osVersion, forHTTPHeaderField: "x-ver-os")
        request.setValue(Device.model, forHTTPHeaderField: "x-device-model")
        request.setValue("close", forHTTPHeaderField: "Connection")
        // новое соединение на каждый запрос: на части сетей долгие соединения через CDN «замирают»
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LitError(netError) }
        switch http.statusCode {
        case 200 ..< 300: break
        case 404: throw LitError("Подписка не найдена. Проверьте ссылку или получите новую в боте.")
        case 403: throw LitError("Подписка отключена. Обратитесь в поддержку.")
        case 500 ..< 600: throw URLError(.badServerResponse)
        default: throw LitError("Сервер подписки ответил ошибкой (\(http.statusCode)).")
        }
        let info = parseHeaders(http)
        let config = try parseBody(data)
        let servers = Self.servers(in: config)
        if servers.isEmpty {
            throw LitError("В подписке нет доступных серверов. Обновите подписку позже или напишите в поддержку.")
        }
        if servers.count == 1, servers[0].port <= 1 {
            // заглушка сервера подписок: устройство не принято (например, превышен лимит устройств)
            throw LitError("Сервер подписки не выдал серверы для этого устройства. Возможно, превышен лимит устройств — освободите место в боте в разделе «Мои устройства».")
        }
        return Loaded(info: info, config: config, servers: servers)
    }

    static func parseHeaders(_ http: HTTPURLResponse) -> SubscriptionInfo {
        var info = SubscriptionInfo()
        if let raw = http.value(forHTTPHeaderField: "subscription-userinfo") {
            for part in raw.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                let number = Double(kv[1]) ?? 0
                switch kv[0].lowercased() {
                case "upload": info.upload = Int64(number)
                case "download": info.download = Int64(number)
                case "total": info.total = Int64(number)
                case "expire": info.expire = number
                default: break
                }
            }
        }
        info.title = decodeHeader(http.value(forHTTPHeaderField: "profile-title"))
        info.announce = decodeHeader(http.value(forHTTPHeaderField: "announce"))
        info.supportURL = http.value(forHTTPHeaderField: "support-url") ?? ""
        if let hours = Double(http.value(forHTTPHeaderField: "profile-update-interval") ?? ""), hours > 0 {
            info.updateHours = hours
        }
        return info
    }

    /// Значение может быть закодировано как «base64:…».
    static func decodeHeader(_ value: String?) -> String {
        guard var v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return "" }
        if v.lowercased().hasPrefix("base64:") {
            v = String(v.dropFirst(7))
            if let decoded = base64Decode(v) { return decoded }
        }
        return v
    }

    static func base64Decode(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        while t.count % 4 != 0 { t += "=" }
        guard let data = Data(base64Encoded: t) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseBody(_ data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw LitError("Сервер подписки вернул пустой ответ.")
        }
        if text.hasPrefix("{") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw LitError("Не удалось прочитать конфигурацию подписки.")
            }
            return json
        }
        let list = text.contains("://") ? text : (base64Decode(text) ?? "")
        let outbounds = list.split(whereSeparator: \.isNewline).compactMap { URIParser.outbound(String($0)) }
        if outbounds.isEmpty {
            throw LitError("Формат подписки не поддерживается.")
        }
        return ConfigBuilder.template(outbounds: outbounds)
    }

    static let groupTypes: Set<String> = ["selector", "urltest", "direct", "block", "dns"]

    static func servers(in config: [String: Any]) -> [Server] {
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        var result: [Server] = []
        for o in outbounds {
            let type = o["type"] as? String ?? ""
            guard !groupTypes.contains(type), let tag = o["tag"] as? String else { continue }
            let port = (o["server_port"] as? NSNumber)?.intValue ?? 0
            result.append(Server(tag: tag, type: type, host: o["server"] as? String ?? "", port: port))
        }
        let endpoints = config["endpoints"] as? [[String: Any]] ?? []
        for e in endpoints {
            guard let tag = e["tag"] as? String else { continue }
            let peer = (e["peers"] as? [[String: Any]])?.first
            result.append(Server(tag: tag, type: e["type"] as? String ?? "wireguard", host: peer?["address"] as? String ?? "", port: (peer?["port"] as? NSNumber)?.intValue ?? 0))
        }
        return result
    }
}

// MARK: - Сборка итоговой конфигурации

struct ConnectionSettings: Codable, Equatable {
    enum Routing: String, Codable, CaseIterable { case all, ruDirect }

    var routing: Routing = .all
    var dns: String = "auto" // auto или IP-адрес
    var ipv6 = true
    var connectOnLaunch = false

    struct DNSPreset: Identifiable, Hashable {
        var id: String { address }
        let name: String
        let address: String
    }

    static let dnsPresets: [DNSPreset] = [
        DNSPreset(name: "Google", address: "8.8.8.8"),
        DNSPreset(name: "Cloudflare", address: "1.1.1.1"),
        DNSPreset(name: "Яндекс", address: "77.88.8.8"),
        DNSPreset(name: "AdGuard", address: "94.140.14.14"),
    ]
}

enum ConfigBuilder {
    static let selectorTag = "proxy"
    static let autoTag = "auto"

    /// Полная конфигурация для подписки в виде списка ссылок.
    static func template(outbounds: [[String: Any]]) -> [String: Any] {
        [
            "log": ["disabled": true],
            "dns": [
                "servers": [
                    ["type": "tls", "tag": "dns-remote", "server": "1.1.1.1"],
                    ["type": "local", "tag": "dns-local"],
                ],
                "final": "dns-remote",
            ] as [String: Any],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
                "stack": "mixed",
            ] as [String: Any]],
            "outbounds": outbounds + [["type": "direct", "tag": "direct"]],
            "route": [
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["ip_is_private": true, "outbound": "direct"],
                ] as [[String: Any]],
                "auto_detect_interface": true,
                "default_domain_resolver": "dns-local",
            ] as [String: Any],
        ]
    }

    /// Конфигурация для туннеля: выбранный сервер или автовыбор, настройки пользователя, без лишнего для iOS.
    static func build(_ source: [String: Any], selected: String, settings: ConnectionSettings) throws -> String {
        var config = source
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let groupTags = Set(outbounds.filter { ["selector", "urltest"].contains($0["type"] as? String ?? "") }.compactMap { $0["tag"] as? String })
        outbounds.removeAll { ["selector", "urltest"].contains($0["type"] as? String ?? "") }
        let servers = SubscriptionLoader.servers(in: config).map(\.tag)
        guard !servers.isEmpty else { throw LitError("В подписке нет серверов.") }
        if !outbounds.contains(where: { ($0["type"] as? String) == "direct" }) {
            outbounds.append(["type": "direct", "tag": "direct"])
        }
        let chosen = servers.contains(selected) ? selected : autoTag
        var groups: [[String: Any]] = []
        if servers.count > 1 {
            groups.append([
                "type": "selector", "tag": selectorTag,
                "outbounds": [autoTag] + servers,
                "default": chosen,
                "interrupt_exist_connections": true,
            ])
            groups.append([
                "type": "urltest", "tag": autoTag,
                "outbounds": servers,
                "url": "https://www.gstatic.com/generate_204",
                "interval": "3m",
                "tolerance": 50,
            ])
        } else {
            groups.append(["type": "selector", "tag": selectorTag, "outbounds": servers, "default": servers[0]])
        }
        config["outbounds"] = groups + outbounds

        // маршруты: старые группы → наш селектор
        var route = config["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        for i in rules.indices {
            if let o = rules[i]["outbound"] as? String, groupTags.contains(o) { rules[i]["outbound"] = selectorTag }
        }
        if settings.routing == .ruDirect {
            let rule: [String: Any] = ["domain_suffix": ["ru", "su", "xn--p1ai"], "outbound": "direct"]
            let index = (rules.firstIndex { ($0["action"] as? String) == "hijack-dns" }).map { $0 + 1 } ?? rules.count
            rules.insert(rule, at: min(index, rules.count))
        }
        route["rules"] = rules
        route["final"] = selectorTag
        route["auto_detect_interface"] = true
        config["route"] = route

        // DNS
        var dns = config["dns"] as? [String: Any] ?? [:]
        var dnsServers = dns["servers"] as? [[String: Any]] ?? []
        for i in dnsServers.indices {
            if let d = dnsServers[i]["detour"] as? String, groupTags.contains(d) { dnsServers[i]["detour"] = selectorTag }
        }
        if settings.dns != "auto" {
            dnsServers.removeAll { ($0["tag"] as? String) == "user-dns" }
            dnsServers.append(["type": "udp", "tag": "user-dns", "server": settings.dns])
            dns["final"] = "user-dns"
        }
        if !settings.ipv6 { dns["strategy"] = "ipv4_only" }
        dns["servers"] = dnsServers
        config["dns"] = dns

        // только TUN; без системного прокси и имени интерфейса (на iOS их задаёт система)
        var inbounds = (config["inbounds"] as? [[String: Any]] ?? []).filter { ($0["type"] as? String) == "tun" }
        if inbounds.isEmpty {
            inbounds = (template(outbounds: [])["inbounds"] as? [[String: Any]]) ?? []
        }
        for i in inbounds.indices {
            inbounds[i].removeValue(forKey: "platform")
            inbounds[i].removeValue(forKey: "interface_name")
            if !settings.ipv6, let addrs = inbounds[i]["address"] as? [String] {
                inbounds[i]["address"] = addrs.filter { !$0.contains(":") }
            }
        }
        config["inbounds"] = inbounds
        config.removeValue(forKey: "experimental") // clash_api и кэш не нужны: память расширения ограничена
        config["log"] = ["disabled": true, "level": "warn"]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw LitError("Не удалось собрать конфигурацию.") }
        return text
    }
}

// MARK: - Ссылки vless:// trojan:// ss:// hysteria2:// vmess://

enum URIParser {
    static func outbound(_ raw: String) -> [String: Any]? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let schemeEnd = line.range(of: "://") else { return nil }
        let scheme = line[..<schemeEnd.lowerBound].lowercased()
        switch scheme {
        case "vless", "trojan": return vlessTrojan(line, scheme: scheme)
        case "ss": return shadowsocks(line)
        case "hysteria2", "hy2": return hysteria2(line)
        case "vmess": return vmess(line)
        default: return nil
        }
    }

    private static func name(_ comps: URLComponents, fallback: String) -> String {
        let n = comps.fragment?.removingPercentEncoding ?? comps.fragment ?? ""
        return n.isEmpty ? fallback : n
    }

    private static func query(_ comps: URLComponents) -> [String: String] {
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        return q
    }

    private static func tls(_ q: [String: String], host: String, forced: Bool = false) -> [String: Any]? {
        let security = q["security"] ?? (forced ? "tls" : "none")
        guard security == "tls" || security == "reality" else { return nil }
        var tls: [String: Any] = ["enabled": true]
        let sni = q["sni"] ?? q["peer"] ?? ""
        tls["server_name"] = sni.isEmpty ? host : sni
        if let fp = q["fp"], !fp.isEmpty { tls["utls"] = ["enabled": true, "fingerprint": fp] }
        if let alpn = q["alpn"], !alpn.isEmpty { tls["alpn"] = alpn.split(separator: ",").map(String.init) }
        if q["allowInsecure"] == "1" || q["insecure"] == "1" { tls["insecure"] = true }
        if security == "reality" {
            tls["reality"] = ["enabled": true, "public_key": q["pbk"] ?? "", "short_id": q["sid"] ?? ""]
            if tls["utls"] == nil { tls["utls"] = ["enabled": true, "fingerprint": "chrome"] }
        }
        return tls
    }

    private static func transport(_ q: [String: String]) -> [String: Any]?? {
        switch q["type"] ?? "tcp" {
        case "tcp", "raw", "": return .some(nil)
        case "ws":
            var t: [String: Any] = ["type": "ws", "path": q["path"] ?? "/"]
            if let h = q["host"], !h.isEmpty { t["headers"] = ["Host": h] }
            return .some(t)
        case "grpc": return .some(["type": "grpc", "service_name": q["serviceName"] ?? ""])
        case "httpupgrade":
            var t: [String: Any] = ["type": "httpupgrade", "path": q["path"] ?? "/"]
            if let h = q["host"], !h.isEmpty { t["host"] = h }
            return .some(t)
        case "http", "h2":
            var t: [String: Any] = ["type": "http", "path": q["path"] ?? "/"]
            if let h = q["host"], !h.isEmpty { t["host"] = [h] }
            return .some(t)
        default: return nil // xhttp и др. ядро не поддерживает
        }
    }

    private static func vlessTrojan(_ line: String, scheme: String) -> [String: Any]? {
        guard let comps = URLComponents(string: line), let host = comps.host, let port = comps.port,
              let user = comps.user?.removingPercentEncoding ?? comps.user, !user.isEmpty
        else { return nil }
        let q = query(comps)
        guard let transport = transport(q) else { return nil }
        var o: [String: Any] = ["type": scheme, "tag": name(comps, fallback: "\(host):\(port)"), "server": host, "server_port": port]
        if scheme == "vless" {
            o["uuid"] = user
            if let flow = q["flow"], !flow.isEmpty { o["flow"] = flow }
        } else {
            o["password"] = user
        }
        if let tls = tls(q, host: host, forced: scheme == "trojan") { o["tls"] = tls }
        if let transport { o["transport"] = transport }
        return o
    }

    private static func shadowsocks(_ line: String) -> [String: Any]? {
        var body = String(line.dropFirst(5))
        var tag = ""
        if let hash = body.firstIndex(of: "#") {
            tag = String(body[body.index(after: hash)...]).removingPercentEncoding ?? ""
            body = String(body[..<hash])
        }
        if let qm = body.firstIndex(of: "?") { body = String(body[..<qm]) }
        var userinfo: String
        var hostport: String
        if let at = body.lastIndex(of: "@") {
            userinfo = String(body[..<at])
            hostport = String(body[body.index(after: at)...])
            if let decoded = SubscriptionLoader.base64Decode(userinfo), decoded.contains(":") { userinfo = decoded }
            else { userinfo = userinfo.removingPercentEncoding ?? userinfo }
        } else {
            guard let decoded = SubscriptionLoader.base64Decode(body), let at = decoded.lastIndex(of: "@") else { return nil }
            userinfo = String(decoded[..<at])
            hostport = String(decoded[decoded.index(after: at)...])
        }
        hostport = hostport.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let colon = userinfo.firstIndex(of: ":"), let pc = hostport.lastIndex(of: ":"),
              let port = Int(hostport[hostport.index(after: pc)...])
        else { return nil }
        let host = String(hostport[..<pc]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return [
            "type": "shadowsocks",
            "tag": tag.isEmpty ? "\(host):\(port)" : tag,
            "server": host, "server_port": port,
            "method": String(userinfo[..<colon]),
            "password": String(userinfo[userinfo.index(after: colon)...]),
        ]
    }

    private static func hysteria2(_ line: String) -> [String: Any]? {
        guard let comps = URLComponents(string: line), let host = comps.host else { return nil }
        let q = query(comps)
        let port = comps.port ?? 443
        var tls: [String: Any] = ["enabled": true, "server_name": (q["sni"] ?? "").isEmpty ? host : q["sni"]!]
        if q["insecure"] == "1" { tls["insecure"] = true }
        var o: [String: Any] = [
            "type": "hysteria2", "tag": name(comps, fallback: "\(host):\(port)"),
            "server": host, "server_port": port,
            "password": comps.user?.removingPercentEncoding ?? comps.user ?? "",
            "tls": tls,
        ]
        if let obfs = q["obfs"], !obfs.isEmpty { o["obfs"] = ["type": obfs, "password": q["obfs-password"] ?? ""] }
        return o
    }

    private static func vmess(_ line: String) -> [String: Any]? {
        guard let text = SubscriptionLoader.base64Decode(String(line.dropFirst(8))),
              let j = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        func s(_ k: String) -> String { (j[k] as? String) ?? (j[k].map { "\($0)" } ?? "") }
        guard let port = Int(s("port")), !s("add").isEmpty else { return nil }
        var q: [String: String] = ["type": s("net"), "path": s("path"), "host": s("host"), "serviceName": s("path"), "sni": s("sni"), "fp": s("fp")]
        q["security"] = s("tls") == "tls" ? "tls" : "none"
        guard let transport = transport(q) else { return nil }
        var o: [String: Any] = [
            "type": "vmess", "tag": s("ps").isEmpty ? "\(s("add")):\(port)" : s("ps"),
            "server": s("add"), "server_port": port, "uuid": s("id"),
            "security": s("scy").isEmpty ? "auto" : s("scy"),
            "alter_id": Int(s("aid")) ?? 0,
        ]
        if let tls = tls(q, host: s("add")) { o["tls"] = tls }
        if let transport { o["transport"] = transport }
        return o
    }
}
