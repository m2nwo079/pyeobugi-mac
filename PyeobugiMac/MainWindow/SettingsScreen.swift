import PostureCore
import SwiftUI

// Binds to the overlay's settings, which the menu also uses, so a change on either side shows on both
struct SettingsScreen: View {
    @Bindable var overlay: TurtleOverlay
    let monitor: PostureMonitor
    let recalibrate: () -> Void

    var body: some View {
        Text("설정").textStyle(.title).foregroundStyle(Color.grey900)

        Card {
            Text("자세 교정").textStyle(.bodyBold).foregroundStyle(Color.grey900)
            VStack(alignment: .leading, spacing: 24) {
                labels("교정 강도", "강할수록 조금만 숙여도 바로 알려줘요")
                SensitivitySlider(value: $overlay.sensitivity)
            }
            HStack {
                labels("기준 자세", "자리나 모니터 위치가 바뀌었다면 다시 잡아주세요")
                Spacer()
                Button(action: recalibrate) {
                    HStack(spacing: 4) {
                        Text("기준 다시 잡기")
                        Image("IconRefresh").renderingMode(.template)
                    }
                }
                .buttonStyle(FilledButtonStyle(fill: false))
                .disabled(monitor.camera == .denied)
            }
        }

        Card {
            Text("기능").textStyle(.bodyBold).foregroundStyle(Color.grey900)
            feature("공부 타이머", "뽀모도로 타이머를 함께 사용해요", $overlay.studyTimerOn)
            feature("스트레칭 알림", "오래 앉아 있으면 스트레칭을 권해요", $overlay.stretchReminder)
            feature("거북이 오버레이 표시", "자세가 무너지면 화면 위에 거북이가 나타나요", $overlay.isVisible)
            feature("전체 화면에서도 표시", "다른 앱을 전체 화면으로 쓸 때도 거북이와 타이머를 띄워요", $overlay.overFullScreen)
        }
    }

    private func labels(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textStyle(.bodyBold).foregroundStyle(Color.grey900)
            Text(description).textStyle(.label).foregroundStyle(Color.grey700)
        }
    }

    private func feature(_ title: String, _ description: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            labels(title, description)
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(PillToggleStyle())
        }
    }
}

// 52×30 pill with a 24-point knob inset by 3
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.main2 : .grey300)
                .frame(width: 52, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: Color(red: 26 / 255, green: 40 / 255, blue: 46 / 255).opacity(0.05), radius: 8, x: 4, y: 4)
                        .padding(3)
                }
                .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// Three steps: drag or click the track, click a step name, or use the arrow keys
private struct SensitivitySlider: View {
    @Binding var value: Sensitivity

    private static let steps = Sensitivity.allCases
    private static let animation = Animation.easeOut(duration: 0.15)

    private var index: Int { Self.steps.firstIndex(of: value) ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let x = geometry.size.width * CGFloat(index) / CGFloat(Self.steps.count - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.grey300).frame(height: 8)
                    Capsule().fill(Color.main3).frame(width: x, height: 9).offset(y: -0.5)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(Color.main3, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: x - 8)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let ratio = drag.location.x / max(geometry.size.width, 1)
                    select(Int((ratio * CGFloat(Self.steps.count - 1)).rounded()))
                })
            }
            .frame(height: 8)
            HStack {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { offset, step in
                    if offset > 0 { Spacer() }
                    Button(step.label) { select(offset) }
                        .buttonStyle(.plain)
                        .textStyle(offset <= index ? .labelBold : .label)
                        .foregroundStyle(offset <= index ? Color.grey900 : .grey700)
                }
            }
        }
        .animation(Self.animation, value: value)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { select(index - 1); return .handled }
        .onKeyPress(.rightArrow) { select(index + 1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("교정 강도")
        .accessibilityValue(value.label)
        .accessibilityAdjustableAction { direction in
            select(index + (direction == .increment ? 1 : -1))
        }
    }

    private func select(_ offset: Int) {
        let step = Self.steps[min(max(offset, 0), Self.steps.count - 1)]
        if step != value { value = step }
    }
}

extension Sensitivity {
    var label: String {
        switch self {
        case .loose: "느슨하게"
        case .normal: "보통"
        case .strict: "엄격하게"
        }
    }
}
