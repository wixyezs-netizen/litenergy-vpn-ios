import Foundation

/// Запросы к существующему API сайта LitEnergy (вход по почте или через бота, тарифы, ссылка на подписку).
/// Каждый запрос — новая сессия и новое соединение.
enum Api {
    static let base = Links.site

    struct Account {
        let token: String
        let subscriptionURL: String?
        let title: String
    }

    struct Bootstrap {
        let subscriptionURL: String?
        let status: String
        let tariffs: [Tariff]
    }

    static func json(_ method: String, _ path: String, body: [String: Any]? = nil, session token: String? = nil) async throws -> [String: Any] {
        var lastError: Error = LitError(SubscriptionLoader.netError)
        for attempt in 0 ..< 3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000) }
            do {
                return try await once(method, path, body: body, session: token)
            } catch let error as LitError {
                throw error
            } catch {
                lastError = LitError(SubscriptionLoader.netError)
                if method == "POST" { break } // не повторяем отправку кода
            }
        }
        throw lastError
    }

    private static func once(_ method: String, _ path: String, body: [String: Any]?, session token: String?) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw LitError("Неверный адрес") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("LitEnergyVPN/\(Device.appVersion) (iOS \(Device.osVersion))", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue(token, forHTTPHeaderField: "X-LitEnergy-Session") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if !(200 ..< 300).contains(http.statusCode) {
            if [502, 503, 504, 520, 521, 522, 523, 524].contains(http.statusCode), json.isEmpty {
                throw URLError(.badServerResponse)
            }
            if http.statusCode == 401 { throw LitError((json["message"] as? String) ?? "Войдите заново.") }
            throw LitError((json["message"] as? String) ?? "Ошибка сервера (\(http.statusCode))")
        }
        return json
    }

    // MARK: вход по почте

    static func requestEmailCode(_ email: String) async throws {
        _ = try await json("POST", "/api/web/auth/email/request", body: ["email": email, "device_id": Device.hwid])
    }

    static func verifyEmailCode(_ email: String, code: String) async throws -> Account {
        let j = try await json("POST", "/api/web/auth/email/verify", body: ["email": email, "code": code, "device_id": Device.hwid])
        guard let token = j["token"] as? String, !token.isEmpty else { throw LitError("Не удалось войти. Попробуйте ещё раз.") }
        return Account(token: token, subscriptionURL: j["subscription_url"] as? String, title: email)
    }

    // MARK: вход через бота

    static func startBotLogin() async throws -> (code: String, url: String) {
        let j = try await json("GET", "/api/web/auth/request-bot?client=app")
        guard let code = j["code"] as? String, let url = j["url"] as? String else { throw LitError("Не удалось получить ссылку на бота.") }
        return (code, url)
    }

    /// nil — пользователь ещё не подтвердил вход в боте.
    static func pollBotLogin(_ code: String) async throws -> Account? {
        let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        let j = try await json("GET", "/api/web/auth/poll-bot?code=" + escaped)
        guard (j["status"] as? String) == "authenticated", let token = j["token"] as? String else { return nil }
        let user = j["user"] as? [String: Any] ?? [:]
        let username = (user["username"] as? String).map { "@" + $0 } ?? (user["first_name"] as? String ?? "Telegram")
        return Account(token: token, subscriptionURL: nil, title: username)
    }

    // MARK: данные кабинета

    static func bootstrap(_ token: String) async throws -> Bootstrap {
        let j = try await json("GET", "/api/miniapp/bootstrap", session: token)
        let sub = j["subscription"] as? [String: Any] ?? [:]
        let rows = j["tariffs"] as? [[String: Any]] ?? []
        let tariffs = rows.compactMap { row -> Tariff? in
            guard let code = row["code"] as? String else { return nil }
            let days = (row["days"] as? NSNumber)?.intValue ?? 0
            return Tariff(code: code, days: days, title: row["title"] as? String ?? "\(days) дней", price: (row["price"] as? String) ?? "\(row["price"] ?? "0")")
        }
        return Bootstrap(subscriptionURL: sub["url"] as? String, status: sub["status"] as? String ?? "NONE", tariffs: tariffs)
    }

    static func refreshSession(_ token: String) async throws -> String? {
        let j = try await json("POST", "/api/web/auth/refresh", body: [:], session: token)
        return j["token"] as? String
    }
}
