import Network
import SwiftUI

// MARK: - Серверы

struct ServersSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pings: [String: Int] = [:]
    @State private var measuring = false
    @State private var query = ""

    private var servers: [Server] {
        let all = state.current?.servers ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.tag.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "Серверы") { dismiss() }
                if (state.current?.servers.count ?? 0) > 6 {
                    TextField("", text: $query, prompt: Text("Поиск").foregroundColor(.w1Dim))
                        .font(ui(16)).foregroundColor(.white)
                        .padding(.horizontal, 16).frame(minHeight: 46).card(16)
                }
                RowGroup {
                    SelectRow(title: "Автовыбор", subtitle: "Самый быстрый сервер подбирается автоматически",
                              selected: state.selectedServer == ConfigBuilder.autoTag) { choose(ConfigBuilder.autoTag) }
                }
                SectionTitle(text: "Локации")
                RowGroup {
                    ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 { Divider().background(Color.w1Border).padding(.leading, 48) }
                        SelectRow(title: server.tag, subtitle: server.protocolName, trailing: pingText(server),
                                  selected: state.selectedServer == server.tag) { choose(server.tag) }
                    }
                }
                Button {
                    Task { await measure() }
                } label: {
                    HStack(spacing: 8) {
                        if measuring { ProgressView().tint(.white) } else { Image(systemName: "speedometer") }
                        Text(measuring ? "Проверяем…" : "Проверить пинг")
                    }
                    .font(ui(15, .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 46).card(16)
                }
                .buttonStyle(.plain)
                .disabled(measuring)
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheetBackground()
        .task { await measure() }
    }

    private func choose(_ tag: String) {
        state.selectServer(tag)
        dismiss()
    }

    private func pingText(_ server: Server) -> String {
        if server.isUDP { return "" }
        guard let ms = pings[server.tag] else { return measuring ? "…" : "" }
        return ms < 0 ? "нет ответа" : "\(ms) мс"
    }

    private func measure() async {
        guard !measuring, !state.demo else {
            if state.demo { pings = Dictionary(uniqueKeysWithValues: (state.current?.servers ?? []).enumerated().map { ($1.tag, [38, 52, 61, 44][$0 % 4]) }) }
            return
        }
        measuring = true
        defer { measuring = false }
        let list = (state.current?.servers ?? []).filter { !$0.isUDP && !$0.host.isEmpty && $0.port > 0 }
        await withTaskGroup(of: (String, Int).self) { group in
            for server in list {
                group.addTask { (server.tag, await Ping.tcp(host: server.host, port: server.port)) }
            }
            for await (tag, ms) in group {
                pings[tag] = ms
            }
        }
    }
}

/// Время установки TCP-соединения с сервером, мс (-1 — нет ответа).
enum Ping {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        /// true — только для первого вызова.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func tcp(host: String, port: Int, timeout: Double = 3) async -> Int {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return -1 }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let start = Date()
            let once = Once()
            let finish: @Sendable (Int) -> Void = { value in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled, .waiting: finish(-1)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(-1) }
        }
    }
}

// MARK: - Тарифы

struct PlansSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "Тарифы") { dismiss() }
                Text("Оплата проходит в нашем боте или на сайте. После оплаты подписка продлится автоматически — обновите её в приложении.")
                    .font(ui(14)).foregroundColor(.w1Muted)
                RowGroup {
                    ForEach(Array(state.tariffs.enumerated()), id: \.element.id) { index, tariff in
                        if index > 0 { Divider().background(Color.w1Border).padding(.leading, 16) }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tariff.title).font(ui(16, .semibold)).foregroundColor(.white)
                                Text("\(tariff.days) дн.").font(ui(13)).foregroundColor(.w1Muted)
                            }
                            Spacer()
                            Text(tariff.priceText).font(ui(17, .bold)).foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }
                .padding(.top, 6)
                PrimaryButton(title: "Оплатить в боте") { openLink(Links.bot) }.padding(.top, 10)
                PillButton(icon: "safari", title: "Оплатить на сайте") { openLink(Links.plans) }
                Text("Средства на балансе можно потратить только на оплату подписки, вывод недоступен. Лимит — 10 000 ₽ на один платёж и на баланс.")
                    .font(ui(12)).foregroundColor(.w1Dim)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheetBackground()
        .mediumSheet()
    }
}

// MARK: - Меню

struct MenuSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let onPlans: () -> Void
    let onSubscriptions: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "Меню") { dismiss() }
                SheetItem(title: "Купить или продлить", subtitle: "Тарифы, оплата в боте или на сайте", action: onPlans)
                SheetItem(title: "Мои подписки", subtitle: "\(state.subscriptions.count) · добавить или переключить", action: onSubscriptions)
                SheetItem(title: "Поддержка", subtitle: "Ответим в Telegram") { openLink(Links.support) }
                SheetItem(title: "Наш канал", subtitle: "Новости и обновления") { openLink(Links.channel) }
                SheetItem(title: "Пользовательское соглашение", subtitle: "Условия использования сервиса") { openLink(Links.terms) }
                SheetItem(title: "Политика конфиденциальности", subtitle: "Как мы обращаемся с данными") { openLink(Links.privacy) }
                SheetItem(title: "Скачать последнюю версию", subtitle: "Страница выпусков приложения") { openLink(Links.releases) }
                Text("LitEnergy VPN · версия \(Device.appVersion)")
                    .font(ui(13)).foregroundColor(.w1Dim).padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheetBackground()
    }
}

// MARK: - Настройки

struct SettingsSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @State private var customDns = ""
    @State private var dnsError: String?
    @State private var showDiagnostics = false
    @State private var confirmDelete = false
    @State private var refreshMessage: String?

    private var isCustomDns: Bool {
        state.settings.dns != "auto" && !ConnectionSettings.dnsPresets.contains { $0.address == state.settings.dns }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "Настройки") { dismiss() }

                SectionTitle(text: "Маршрутизация")
                RowGroup {
                    SelectRow(title: "Весь трафик через VPN", selected: state.settings.routing == .all) { state.settings.routing = .all }
                    Divider().background(Color.w1Border).padding(.leading, 48)
                    SelectRow(title: "Российские сайты напрямую", subtitle: "Домены .ru, .su и .рф открываются без VPN",
                              selected: state.settings.routing == .ruDirect) { state.settings.routing = .ruDirect }
                }

                SectionTitle(text: "DNS")
                RowGroup {
                    SelectRow(title: "Как в подписке", selected: state.settings.dns == "auto") { state.settings.dns = "auto" }
                    ForEach(ConnectionSettings.dnsPresets) { preset in
                        Divider().background(Color.w1Border).padding(.leading, 48)
                        SelectRow(title: preset.name, trailing: preset.address, selected: state.settings.dns == preset.address) {
                            state.settings.dns = preset.address
                        }
                    }
                    Divider().background(Color.w1Border).padding(.leading, 48)
                    SelectRow(title: "Свой адрес", trailing: isCustomDns ? state.settings.dns : "", selected: isCustomDns) {
                        customDns = isCustomDns ? state.settings.dns : ""
                    }
                    HStack(spacing: 10) {
                        TextField("", text: $customDns, prompt: Text("Например, 9.9.9.9").foregroundColor(.w1Dim))
                            .font(ui(16)).foregroundColor(.white)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Применить") { applyCustomDns() }
                            .font(ui(14, .semibold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                if let dnsError { Text(dnsError).font(ui(13)).foregroundColor(.w1Red) }

                SectionTitle(text: "Подключение")
                RowGroup {
                    ToggleRow(title: "IPv6", subtitle: "Выключите, если сайты открываются медленно", isOn: $state.settings.ipv6)
                    Divider().background(Color.w1Border).padding(.leading, 16)
                    ToggleRow(title: "Подключаться при запуске", subtitle: "VPN включится при открытии приложения", isOn: $state.settings.connectOnLaunch)
                }

                SectionTitle(text: "Подписка")
                SheetItem(title: "Обновить подписку", subtitle: refreshMessage ?? "Загрузить актуальные серверы и срок") {
                    Task {
                        refreshMessage = "Обновляем…"
                        do {
                            try await state.refresh()
                            refreshMessage = "Готово"
                        } catch {
                            refreshMessage = error.localizedDescription
                        }
                    }
                }
                SheetItem(title: "Диагностика VPN", subtitle: "Проверить подпись приложения и разрешение VPN") { showDiagnostics = true }
                if state.isLoggedIn {
                    SheetItem(title: "Выйти из аккаунта", subtitle: state.accountTitle ?? "Подписки на телефоне останутся") { state.signOut() }
                }
                Button {
                    confirmDelete = true
                } label: {
                    Text("Удалить подписку с телефона")
                        .font(ui(16, .semibold)).foregroundColor(.w1Red)
                        .frame(maxWidth: .infinity, minHeight: 50).card(18)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                Text("Версия \(Device.appVersion)").font(ui(13)).foregroundColor(.w1Dim).padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheetBackground()
        .alert("Диагностика VPN", isPresented: $showDiagnostics) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(VPNDiagnostics.current().report)
        }
        .confirmationDialog("Удалить подписку с этого телефона?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if vpn.isConnected || vpn.isBusy { vpn.disconnect() }
                if let id = state.currentId { state.remove(id) }
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сама подписка не отменяется — её можно добавить снова по ссылке.")
        }
    }

    private func applyCustomDns() {
        let value = customDns.trimmingCharacters(in: .whitespaces)
        guard IPv4Address(value) != nil || IPv6Address(value) != nil else {
            dnsError = "Введите IP-адрес DNS, например 9.9.9.9"
            return
        }
        dnsError = nil
        state.settings.dns = value
    }
}

// MARK: - Мои подписки

struct SubscriptionsSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showScanner = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "Мои подписки") { dismiss() }
                RowGroup {
                    ForEach(Array(state.subscriptions.enumerated()), id: \.element.id) { index, sub in
                        if index > 0 { Divider().background(Color.w1Border).padding(.leading, 48) }
                        SelectRow(title: sub.name, subtitle: sub.info.expireLine + " · " + state.maskedLink(sub.id),
                                  selected: sub.id == state.currentId) {
                            guard sub.id != state.currentId else { return }
                            if vpn.isConnected || vpn.isBusy { vpn.disconnect() }
                            state.currentId = sub.id
                        }
                    }
                }
                SectionTitle(text: "Добавить подписку")
                HStack(spacing: 10) {
                    TextField("", text: $link, prompt: Text("Ссылка на подписку").foregroundColor(.w1Dim))
                        .font(ui(16)).foregroundColor(.white)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Вставить") { link = UIPasteboard.general.string ?? link }
                        .font(ui(14, .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 16).frame(minHeight: 52).card(16)
                PrimaryButton(title: "Добавить", busy: busy, enabled: !link.isEmpty) { Task { await add(link) } }
                PillButton(icon: "qrcode.viewfinder", title: "Сканировать QR-код") { showScanner = true }
                if let error { Text(error).font(ui(13)).foregroundColor(.w1Red) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheetBackground()
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { value in Task { await add(value) } }
        }
    }

    private func add(_ raw: String) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            if vpn.isConnected || vpn.isBusy { vpn.disconnect() }
            try await state.importLink(raw)
            link = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
