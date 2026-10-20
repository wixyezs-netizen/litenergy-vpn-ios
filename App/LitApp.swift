import NetworkExtension
import SwiftUI

@main
struct LitApp: App {
    @StateObject private var state = AppState()
    @StateObject private var vpn = VPNController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(vpn)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var vpn: VPNController
    @State private var importError: String?

    var body: some View {
        Group {
            if state.current != nil {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
        .onOpenURL { url in
            Task {
                do {
                    try await state.importLink(url.absoluteString)
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .alert("Не удалось добавить подписку", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}

/// Чёрный фон и падающие белые точки в верхней четверти экрана.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            FallingDots()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct FallingDots: View {
    var count = 46
    var zone: CGFloat = 0.25 // доля высоты экрана

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height * zone
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for i in 0 ..< count {
                        let seed = Double(i)
                        let x = fract(sin(seed * 12.9898) * 43758.5453) * size.width
                        let speed = 14 + fract(sin(seed * 78.233) * 12345.678) * 30 // pt/s
                        let phase = fract(sin(seed * 3.17) * 9876.54)
                        let r = 0.7 + fract(sin(seed * 5.71) * 4567.89) * 1.3
                        let progress = fract(t * speed / Double(height) + phase)
                        let y = progress * Double(height)
                        let alpha = (1 - progress) * (0.35 + 0.55 * fract(sin(seed * 9.1) * 777.7))
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                    }
                }
                .frame(height: height)
            }
        }
    }

    private func fract(_ v: Double) -> Double {
        v - floor(v)
    }
}

// MARK: - Палитра (как в мини-приложении)

extension Color {
    static let w1Surface = Color(red: 0.086, green: 0.086, blue: 0.086) // #161616
    static let w1Pill = Color(red: 0.133, green: 0.133, blue: 0.133) // #222222
    static let w1Border = Color.white.opacity(0.08)
    static let w1BorderStrong = Color.white.opacity(0.18)
    static let w1Muted = Color(red: 0.557, green: 0.557, blue: 0.576) // #8e8e93
    static let w1Dim = Color(red: 0.388, green: 0.388, blue: 0.4) // #636366
    static let w1Red = Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444
    static let w1Green = Color(red: 0.204, green: 0.78, blue: 0.349) // #34c759
    static let w1Sheet = Color(red: 0.055, green: 0.055, blue: 0.055)
}

func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .default)
}

extension View {
    @ViewBuilder
    func mediumSheet() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }

    func card(_ radius: CGFloat = 24) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.w1Surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.w1Border, lineWidth: 1))
    }

    /// Фон для модальных окон.
    func sheetBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.w1Sheet.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

/// Открыть ссылку (Telegram открывается в приложении, если оно установлено).
@MainActor
func openLink(_ string: String) {
    guard let url = URL(string: string) else { return }
    UIApplication.shared.open(url)
}
