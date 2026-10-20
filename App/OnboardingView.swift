import SwiftUI
import UIKit

/// Добавление подписки: ссылка, QR-код, вход по почте или через Telegram.
struct OnboardingView: View {
    enum Step { case start, link, email, telegram }

    @EnvironmentObject private var state: AppState
    @State private var step: Step = .start
    @State private var link = ""
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var botURL: String?
    @State private var botCode: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if step != .start {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { reset(to: .start) }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 44, height: 44).card(22)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityLabel("Назад")
                }
                switch step {
                case .start: startStep
                case .link: linkStep
                case .email: emailStep
                case .telegram: telegramStep
                }
                if let error {
                    Text(error).font(ui(14)).foregroundColor(.w1Red).padding(.top, 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { value in
                link = value
                Task { await add(value) }
            }
        }
        .task(id: botCode) { await pollBot() }
    }

    // MARK: шаги

    private var startStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            BrandHeader()
            Text("Добавьте подписку, чтобы подключиться")
                .font(ui(16)).foregroundColor(.w1Muted).multilineTextAlignment(.center)
                .padding(.top, 10)
            VStack(spacing: 12) {
                ChoiceCard(icon: "doc.on.clipboard", title: "Вставить ссылку", subtitle: "Ссылка на подписку из бота или личного кабинета") {
                    let clip = UIPasteboard.general.string ?? ""
                    if SubscriptionLoader.normalize(clip) != nil {
                        link = clip
                        Task { await add(clip) }
                    } else {
                        reset(to: .link)
                    }
                }
                ChoiceCard(icon: "qrcode.viewfinder", title: "Сканировать QR-код", subtitle: "QR-код подписки с экрана компьютера или другого телефона") {
                    error = nil
                    showScanner = true
                }
                ChoiceCard(icon: "envelope", title: "Войти по почте", subtitle: "Если покупали подписку на сайте") {
                    reset(to: .email)
                }
                ChoiceCard(icon: "paperplane", title: "Войти через Telegram", subtitle: "Подписка подтянется из бота @VPN_LitEnergy_bot") {
                    reset(to: .telegram)
                    Task { await startBot() }
                }
            }
            .padding(.top, 28)
            if busy || state.updating {
                ProgressView().tint(.white).padding(.top, 18)
            }
            PillButton(icon: "cart", title: "Купить подписку") { openLink(Links.bot) }
                .padding(.top, 22)
            legal.padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Ссылка на подписку", subtitle: "Скопируйте ссылку в боте @VPN_LitEnergy_bot (раздел «Моя подписка») или в личном кабинете на сайте.")
            HStack(spacing: 10) {
                TextField("", text: $link, prompt: Text("https://\(Links.subscriptionHost)/…").foregroundColor(.w1Dim))
                    .font(ui(16))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { Task { await add(link) } }
                Button("Вставить") { link = UIPasteboard.general.string ?? link }
                    .font(ui(14, .semibold)).foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .card(18)
            .padding(.top, 22)
            PrimaryButton(title: "Добавить", busy: busy, enabled: !link.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { await add(link) }
            }
            .padding(.top, 16)
            PillButton(icon: "qrcode.viewfinder", title: "Сканировать QR-код") { showScanner = true }
                .padding(.top, 12)
            PillButton(icon: "cart", title: "Купить подписку") { openLink(Links.bot) }
                .padding(.top, 12)
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Вход по почте", subtitle: codeSent ? "Мы отправили код на \(email). Письмо может прийти в течение минуты — проверьте и папку «Спам»." : "Укажите почту, на которую оформлена подписка. Пришлём код для входа.")
            field("name@mail.ru", text: $email, keyboard: .emailAddress)
                .disabled(codeSent)
                .opacity(codeSent ? 0.6 : 1)
                .padding(.top, 22)
            if codeSent {
                field("Код из письма", text: $code, keyboard: .numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(.top, 12)
                PrimaryButton(title: "Войти", busy: busy, enabled: code.count >= 4) { Task { await verifyEmail() } }
                    .padding(.top, 16)
                Button("Изменить почту") { codeSent = false; code = ""; error = nil }
                    .font(ui(15, .semibold)).foregroundColor(.w1Muted)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            } else {
                PrimaryButton(title: "Получить код", busy: busy, enabled: email.contains("@") && email.contains(".")) {
                    Task { await requestEmail() }
                }
                .padding(.top, 16)
            }
        }
    }

    private var telegramStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Вход через Telegram", subtitle: "Откройте бота и нажмите «Старт». После подтверждения подписка добавится автоматически.")
            VStack(spacing: 14) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 34, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 76, height: 76).card(22)
                if botCode != nil {
                    HStack(spacing: 8) {
                        ProgressView().tint(.w1Muted)
                        Text("Ждём подтверждения в боте…").font(ui(15)).foregroundColor(.w1Muted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
            PrimaryButton(title: "Открыть бота", busy: busy && botURL == nil, enabled: botURL != nil) {
                if let botURL { openLink(botURL) }
            }
            .padding(.top, 26)
        }
    }

    private var legal: some View {
        HStack(spacing: 6) {
            Button("Соглашение") { openLink(Links.terms) }
            Text("·")
            Button("Конфиденциальность") { openLink(Links.privacy) }
            Text("·")
            Button("Поддержка") { openLink(Links.support) }
        }
        .font(ui(13)).foregroundColor(.w1Dim)
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.w1Dim))
            .font(ui(17))
            .foregroundColor(.white)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .card(18)
    }

    // MARK: действия

    private func reset(to next: Step) {
        error = nil
        busy = false
        if next != .telegram { botCode = nil; botURL = nil }
        step = next
    }

    private func add(_ raw: String) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await state.importLink(raw)
        } catch {
            self.error = error.localizedDescription
            if step == .start { step = .link }
        }
    }

    private func requestEmail() async {
        error = nil
        busy = true
        defer { busy = false }
        email = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try await Api.requestEmailCode(email)
            codeSent = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verifyEmail() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            let account = try await Api.verifyEmailCode(email, code: code.trimmingCharacters(in: .whitespaces))
            try await state.signIn(account)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startBot() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await Api.startBotLogin()
            botURL = result.url
            botCode = result.code
            openLink(result.url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ждём «Старт» в боте до 10 минут.
    private func pollBot() async {
        guard let code = botCode else { return }
        for _ in 0 ..< 300 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || botCode != code { return }
            guard let account = try? await Api.pollBotLogin(code) else { continue }
            botCode = nil
            busy = true
            do {
                try await state.signIn(account)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
            return
        }
        botCode = nil
        error = "Время ожидания истекло. Нажмите «Назад» и попробуйте снова."
    }
}
