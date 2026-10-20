import NetworkExtension
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var vpn: VPNController
    @State private var message: String?
    @State private var showMenu = false
    @State private var showSettings = false
    @State private var showServers = false
    @State private var showPlans = false
    @State private var showSubscriptions = false

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            RoundIconButton(icon: "line.3.horizontal", label: "Меню") { showMenu = true }
                            Spacer()
                            RoundIconButton(icon: "gearshape", label: "Настройки") { showSettings = true }
                        }
                        .padding(.top, 4)

                        BrandHeader(compact: true).padding(.top, 2)

                        if let sub = state.current {
                            StatusCard(sub: sub, status: vpn.status, connectedDate: vpn.connectedDate, serverName: state.selectedServerName,
                                       updating: state.updating,
                                       onServers: { showServers = true },
                                       onRenew: { showPlans = true })
                                .padding(.top, 22)
                        }

                        ConnectButton(status: vpn.status, action: toggle)
                            .padding(.top, 22)

                        if let message {
                            Text(message).font(ui(14)).foregroundColor(.w1Red).multilineTextAlignment(.center)
                                .padding(.top, 10)
                        }
                    }
                    Spacer(minLength: 24)
                    VStack(spacing: 12) {
                        LinkCard(icon: "bolt.fill", title: "Купить или продлить", subtitle: "Тарифы от 50 ₽") { showPlans = true }
                        LinkCard(icon: "paperplane.fill", title: "Наш канал", subtitle: "Новости и обновления") { openLink(Links.channel) }
                        LinkCard(icon: "questionmark.bubble.fill", title: "Поддержка", subtitle: "Ответим в Telegram") {
                            openLink(state.current?.info.supportURL.isEmpty == false ? state.current!.info.supportURL : Links.support)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: geo.size.height)
            }
            .refreshable { await refresh(force: true) }
        }
        .task {
            if state.demo {
                // демо для скриншотов сборки: нужное окно открывается само
                switch UserDefaults.standard.string(forKey: "demo_sheet") ?? "" {
                case "servers": showServers = true
                case "plans": showPlans = true
                case "settings": showSettings = true
                case "menu": showMenu = true
                default: break
                }
                return
            }
            await refresh(force: false)
            await state.loadAccount()
            if state.settings.connectOnLaunch, vpn.status == .disconnected || vpn.status == .invalid {
                await connect()
            }
        }
        .onChange(of: vpn.lastError) { value in
            if let value { message = value }
        }
        .onChange(of: state.selectedServer) { _ in applyConfig() }
        .onChange(of: state.settings) { _ in applyConfig() }
        .sheet(isPresented: $showServers) { ServersSheet() }
        .sheet(isPresented: $showPlans) { PlansSheet() }
        .sheet(isPresented: $showMenu) {
            MenuSheet(onPlans: { showMenu = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showPlans = true } },
                      onSubscriptions: { showMenu = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showSubscriptions = true } })
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showSubscriptions) { SubscriptionsSheet() }
    }

    private func toggle() {
        switch vpn.status {
        case .connected, .connecting, .reasserting:
            vpn.disconnect()
        case .disconnecting:
            break
        default:
            Task { await connect() }
        }
    }

    private func connect() async {
        message = nil
        if state.demo { return }
        if let sub = state.current, sub.info.isExpired {
            message = "Подписка закончилась. Продлите её, чтобы подключиться."
            return
        }
        if !state.hasConfig || state.needsRefresh {
            do { try await state.refresh() } catch {
                if !state.hasConfig { message = error.localizedDescription; return }
            }
        }
        do {
            let config = try state.tunnelConfig()
            await vpn.connect(config: config)
        } catch {
            message = error.localizedDescription
        }
    }

    private func refresh(force: Bool) async {
        guard force || state.needsRefresh else { return }
        do {
            try await state.refresh()
            message = nil
            applyConfig()
        } catch {
            if force { message = error.localizedDescription }
        }
    }

    /// Сменили сервер или настройки — сразу применяем к работающему туннелю.
    private func applyConfig() {
        guard vpn.isConnected, let config = try? state.tunnelConfig() else { return }
        Task { await vpn.update(config: config) }
    }
}

/// Карточка статуса, как «Подписка активна | 28 дн.» в мини-приложении.
struct StatusCard: View {
    let sub: Subscription
    let status: NEVPNStatus
    let connectedDate: Date?
    let serverName: String
    let updating: Bool
    let onServers: () -> Void
    let onRenew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(status == .connected ? .black : .white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(status == .connected ? Color.white : Color.w1Pill))
                    .overlay(Circle().strokeBorder(Color.w1BorderStrong, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(title(now: context.date))
                            .font(ui(18, .bold))
                            .foregroundColor(sub.info.isExpired ? .w1Red : .white)
                            .monospacedDigit()
                    }
                    Text(sub.info.expireLine + " · " + sub.info.trafficLine)
                        .font(ui(14)).foregroundColor(.w1Muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                if updating { ProgressView().tint(.w1Muted) }
            }
            if !sub.info.announce.isEmpty {
                Text(sub.info.announce)
                    .font(ui(13)).foregroundColor(.w1Muted)
                    .padding(.top, 12)
            }
            if sub.info.isExpired || sub.info.isTrafficOver {
                PrimaryButton(title: "Продлить", action: onRenew).padding(.top, 16)
            } else {
                Button(action: onServers) {
                    HStack(spacing: 10) {
                        Image(systemName: "globe").font(.system(size: 15, weight: .semibold))
                        Text(serverName).font(ui(16, .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("Сменить").font(ui(14)).foregroundColor(.w1Muted)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.w1Dim)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.w1Pill))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.w1Border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(18)
        .card(26)
    }

    private var icon: String {
        if sub.info.isExpired { return "exclamationmark" }
        return status == .connected ? "checkmark" : "power"
    }

    private func title(now: Date) -> String {
        switch status {
        case .connected:
            guard let since = connectedDate else { return "Подключено" }
            let s = max(0, Int(now.timeIntervalSince(since)))
            return String(format: "Подключено | %02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        case .connecting, .reasserting:
            return "Подключаемся…"
        case .disconnecting:
            return "Отключаемся…"
        default:
            if sub.info.isExpired { return "Подписка закончилась" }
            if sub.info.isTrafficOver { return "Трафик закончился" }
            if let days = sub.info.daysLeft { return "Подписка активна | \(days) дн." }
            return "Подписка активна"
        }
    }
}
