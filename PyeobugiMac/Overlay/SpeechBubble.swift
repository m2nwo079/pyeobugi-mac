import PostureCore
import SwiftUI

extension BubbleKind {
    var message: String {
        switch self {
        case .posture: "목이 앞으로 나왔어요"
        case .distance: "멀어졌어요\n기준을 재설정해주세요."
        case .timerBreak: "휴식 시간이에요"
        case .encourage: "자세가 돌아왔어요!"
        case .greeting: "오늘도 바른 자세!"
        case .stretch: "목을 펴 볼까요?"
        }
    }
}

private extension View {
    func cardShadow() -> some View {
        shadow(color: Color(red: 26 / 255, green: 40 / 255, blue: 46 / 255).opacity(0.05), radius: 8, x: 4, y: 4)
    }
}

// A rounded box with a tail pointing down at the head
struct SpeechBubble: View {
    static let maxWidth: CGFloat = 200
    static let padding: CGFloat = 12
    let message: String

    var body: some View {
        VStack(spacing: -4) {
            Text(message)
                .textStyle(.label)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.main1)
                .frame(maxWidth: Self.maxWidth - 2 * Self.padding)
                .padding(Self.padding)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(Color.main5).cardShadow()
                }
            Tail().fill(Color.main5).frame(width: 12, height: 16)
        }
    }
}

private struct Tail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// Study timer phase and time left
struct TimerPill: View {
    let state: PomodoroState

    var body: some View {
        HStack(spacing: 8) {
            Text(state.phase == .focus ? "집중" : "휴식")
            Text(formatRemaining(state.remaining)).monospacedDigit()
        }
        .textStyle(.labelBold)
        .foregroundStyle(Color.main5)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(Color.main1).cardShadow()
        }
    }
}

// What sits over the head: a bubble, otherwise the running timer
enum HeadContent: Equatable {
    case bubble(BubbleKind)
    case timer(PomodoroState)

    var isTappable: Bool {
        if case .bubble(let kind) = self { kind.isTappable } else { false }
    }
}

struct HeadView: View {
    let content: HeadContent

    var body: some View {
        switch content {
        case .bubble(let kind): SpeechBubble(message: kind.message)
        case .timer(let state): TimerPill(state: state)
        }
    }
}

// The timer at the bottom right while the turtle is hidden
struct CornerTimer: View {
    let timer: StudyTimer

    var body: some View {
        TimerPill(state: timer.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
