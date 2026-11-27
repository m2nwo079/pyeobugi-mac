import AppKit
import SwiftUI

extension Color {
    static let main1 = Color(hex: 0x16202F)
    static let main2 = Color(hex: 0x2A3747)
    static let main3 = Color(hex: 0x74ABB4)
    static let main4 = Color(hex: 0xD3ECEE)
    static let main5 = Color(hex: 0xEEF3F3)
    static let grey100 = Color(hex: 0xF3F5F8)
    static let grey200 = Color(hex: 0xE3E7EC)
    static let grey300 = Color(hex: 0xD0D5DC)
    static let grey700 = Color(hex: 0x5B636E)
    static let grey900 = Color(hex: 0x2D333B)
    static let scrim = Color.main1.opacity(0.8)

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum TextStyle {
    case display, heading, body, bodyBold, label, labelBold, caption

    var size: CGFloat {
        switch self {
        case .display: 40
        case .heading: 24
        case .body, .bodyBold: 16
        case .label, .labelBold: 14
        case .caption: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .heading: .medium
        case .bodyBold, .labelBold: .semibold
        default: .regular
        }
    }

    // Letter spacing in em
    var tracking: CGFloat {
        switch self {
        case .display: -0.03
        case .heading: -0.02
        default: 0
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display: 1.2
        case .heading: 1.3
        case .body, .bodyBold: 1.5
        default: 1.4
        }
    }
}

extension View {
    // Line height is approximate: the system font's default line height is assumed to be about 1.2 times
    // the font size, so only the remainder is added as line spacing. Adjust per style if text looks off.
    func textStyle(_ style: TextStyle) -> some View {
        font(.system(size: style.size, weight: style.weight))
            .tracking(style.size * style.tracking)
            .lineSpacing(style.size * max(style.lineHeight - 1.2, 0))
    }
}

extension NSWorkspace {
    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            open(url)
        }
    }
}

struct FilledButtonStyle: ButtonStyle {
    var secondary = false
    var large = false
    // Body-size label on a small button
    var bodyText = false
    var fill = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(bodyText || large ? .bodyBold : .labelBold)
            .foregroundStyle(secondary ? Color.grey900 : .main5)
            .padding(.horizontal, !large && !secondary ? 16 : 10)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: large ? 52 : 44)
            .background(secondary ? Color.grey300 : .main2, in: RoundedRectangle(cornerRadius: 6))
            .brightness(configuration.isPressed ? 0.1 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct DialogCard: View {
    let title: String
    let message: String
    let confirm: String
    var cancel: String?
    let onConfirm: () -> Void
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).textStyle(.heading).foregroundStyle(Color.grey900)
                Text(message).textStyle(.body).foregroundStyle(Color.grey700)
            }
            .frame(width: 408, alignment: .leading)
            HStack(spacing: 8) {
                if let cancel {
                    Button(cancel, action: onCancel).buttonStyle(FilledButtonStyle(secondary: true))
                }
                Button(confirm, action: onConfirm).buttonStyle(FilledButtonStyle(bodyText: cancel == nil))
            }
            .frame(width: 408)
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(red: 26 / 255, green: 40 / 255, blue: 46 / 255).opacity(0.05), radius: 8, x: 4, y: 4)
    }
}

// Full-window dialog over a scrim
struct ModalDialog: View {
    let title: String
    let message: String
    let confirm: String
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.scrim
            DialogCard(title: title, message: message, confirm: confirm, onConfirm: onConfirm)
        }
    }
}

struct Spinner: View {
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.main2, lineWidth: 5)
            Circle().trim(from: 0, to: 0.25).stroke(Color.main4, lineWidth: 5)
        }
        .frame(width: 46, height: 46)
        .padding(5)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
        .onAppear { spinning = true }
        .accessibilityLabel("로딩 중")
    }
}

struct OnboardingHeader: View {
    // 1-based
    let current: Int

    private static let steps = ["카메라 연결", "얼굴 찾기", "기준 잡기"]

    var body: some View {
        HStack(alignment: .top) {
            Image("Logo")
                .frame(width: 116, height: 30)
                .accessibilityLabel("펴부기")
            Spacer()
            HStack(spacing: 8) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, label in
                    step(index + 1, label)
                }
            }
        }
        .padding([.horizontal, .top], 24)
        .padding(.bottom, 48)
        .background(LinearGradient(colors: [.main1.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func step(_ number: Int, _ label: String) -> some View {
        let done = number < current
        let active = number == current
        return HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(active ? Color.main1 : .main5, lineWidth: 1)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 7, weight: .semibold))
                } else {
                    Text(String(number)).textStyle(.caption)
                }
            }
            .frame(width: 16, height: 16)
            Text(label).textStyle(done ? .labelBold : .label)
        }
        .padding(8)
        .foregroundStyle(active ? Color.main1 : .main5)
        .background(active ? Color.main5 : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct OnboardingPanel<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Text(title).textStyle(.heading).foregroundStyle(.white)
                Text(message).textStyle(.body).foregroundStyle(Color.grey200)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .background(LinearGradient(colors: [.clear, .main1.opacity(0.5)], startPoint: .top, endPoint: .bottom))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
