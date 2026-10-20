import NetworkExtension
import SwiftUI

/// Плитка с логотипом и название — как шапка мини-приложения.
struct BrandHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                .frame(width: compact ? 64 : 76, height: compact ? 64 : 76)
                .card(compact ? 18 : 22)
            Text("LitEnergy VPN")
                .font(ui(compact ? 26 : 30, .heavy))
                .foregroundColor(.white)
        }
    }
}

/// Большая круглая кнопка в монохромном стиле.
struct ConnectButton: View {
    let status: NEVPNStatus
    let action: () -> Void
    @State private var pulse = false

    private var on: Bool { status == .connected }
    private var busy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }

    private var label: String {
        switch status {
        case .connected: return "Отключить"
        case .connecting, .reasserting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        default: return "Подключить"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(on ? (pulse ? 0.16 : 0.08) : (busy ? (pulse ? 0.1 : 0.03) : 0)))
                    .frame(width: 236, height: 236)
                    .blur(radius: 18)
                Circle()
                    .fill(on ? Color.white : Color.w1Surface)
                    .overlay(Circle().strokeBorder(on ? Color.white : Color.w1BorderStrong, lineWidth: 1))
                    .frame(width: 196, height: 196)
                    .shadow(color: .white.opacity(on ? 0.25 : 0), radius: 22)
                VStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.system(size: 58, weight: .regular))
                    Text(label)
                        .font(ui(17, .semibold))
                }
                .foregroundColor(on ? .black : .white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(status == .disconnecting)
        .animation(.easeInOut(duration: 0.25), value: on)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Карточка-ссылка внизу экрана.
struct LinkCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.w1Pill))
                    .overlay(Circle().strokeBorder(Color.w1Border, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ui(16, .semibold)).foregroundColor(.white)
                    Text(subtitle).font(ui(14)).foregroundColor(.w1Muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.w1Dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .card(22)
        }
        .buttonStyle(.plain)
    }
}

struct ChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.w1Pill))
                    .overlay(Circle().strokeBorder(Color.w1Border, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ui(18, .bold)).foregroundColor(.white)
                    Text(subtitle).font(ui(14)).foregroundColor(.w1Muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.w1Dim)
            }
            .padding(18)
            .card(24)
        }
        .buttonStyle(.plain)
    }
}

/// Белая кнопка (главное действие), как «Установить и настроить» в мини-приложении.
struct PrimaryButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(.black)
                } else {
                    Text(title).font(ui(17, .bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(enabled ? .black : .w1Dim)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(enabled ? Color.white : Color.w1Surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(enabled ? Color.clear : Color.w1Border, lineWidth: 1))
            .shadow(color: .white.opacity(enabled ? 0.12 : 0), radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// Тёмная кнопка внутри карточки (как «Сменить тариф»).
struct PillButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(ui(16, .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.w1Pill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.w1Border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct RoundIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.w1Surface))
                .overlay(Circle().strokeBorder(Color.w1Border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SheetItem: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ui(16, .semibold)).foregroundColor(.white)
                    Text(subtitle).font(ui(14)).foregroundColor(.w1Muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.w1Dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .card(18)
        }
        .buttonStyle(.plain)
    }
}

struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(ui(28, .heavy)).foregroundColor(.white)
            Text(subtitle).font(ui(15)).foregroundColor(.w1Muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// Строка выбора с отметкой (для настроек и списков).
struct SelectRow: View {
    let title: String
    var subtitle: String = ""
    var trailing: String = ""
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? .white : .w1Dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ui(16, .semibold)).foregroundColor(.white).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(ui(13)).foregroundColor(.w1Muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if !trailing.isEmpty {
                    Text(trailing).font(ui(14, .medium)).foregroundColor(.w1Muted).monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ui(16, .semibold)).foregroundColor(.white)
                Text(subtitle).font(ui(13)).foregroundColor(.w1Muted)
            }
        }
        .tint(.w1Green)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(ui(12, .semibold))
            .foregroundColor(.w1Dim)
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Тёмная группа строк с разделителями.
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .card(20)
    }
}

/// Заголовок модального окна с кнопкой «Готово».
struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title).font(ui(22, .bold)).foregroundColor(.white)
            Spacer()
            Button("Готово", action: close).font(ui(16, .semibold)).foregroundColor(.white)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}
