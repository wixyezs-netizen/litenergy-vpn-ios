import Foundation

/// Ссылки и тексты сервиса в одном месте.
enum Links {
    static let site = "https://site.litenergyapp.store"
    static let plans = "https://site.litenergyapp.store/plans/"
    static let bot = "https://t.me/VPN_LitEnergy_bot"
    static let support = "https://t.me/wixyezz"
    static let channel = "https://t.me/+65OxDmkfjv04ZDhh"
    static let terms = "https://telegra.ph/Polzovatelskoe-soglasheniya-10-19"
    static let privacy = "https://telegra.ph/Politika-konfidencialnosti-LitEnergy-VPN-10-19-2"
    static let releases = "https://github.com/wixyezs-netizen/litenergy-vpn-ios/releases/latest"
    static let subscriptionHost = "sub.litenergyapp.store"
}

struct Tariff: Codable, Hashable, Identifiable {
    var id: String { code }
    let code: String
    let days: Int
    let title: String
    let price: String // "100.00"

    var priceText: String {
        let value = Double(price) ?? 0
        if value == value.rounded() {
            return "\(Int(value)) ₽"
        }
        return String(format: "%.2f ₽", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Запасные тарифы, если сервер недоступен или пользователь не вошёл.
    static let fallback: [Tariff] = [
        Tariff(code: "d7", days: 7, title: "7 дней", price: "50"),
        Tariff(code: "d30", days: 30, title: "30 дней", price: "100"),
        Tariff(code: "d90", days: 90, title: "90 дней", price: "300"),
        Tariff(code: "d180", days: 180, title: "180 дней", price: "600"),
        Tariff(code: "d365", days: 365, title: "365 дней", price: "1200"),
        Tariff(code: "family3", days: 30, title: "Семейный · 30 дней", price: "150"),
    ]
}
