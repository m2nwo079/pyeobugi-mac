import AppKit
import Observation
import SwiftUI

enum MainScreen {
    case report, settings
}

// Hosts the report and settings screens. The window is kept after closing, so the screen and sidebar
// state survive until the app quits
@Observable
final class MainWindow {
    // Every screen is laid out for this size; a larger window centers it over the background
    static let size = CGSize(width: 1280, height: 832)

    var screen = MainScreen.report
    var collapsed = false

    @ObservationIgnored private let monitor: PostureMonitor
    @ObservationIgnored private let overlay: TurtleOverlay
    @ObservationIgnored private let recalibrate: () -> Void
    @ObservationIgnored private var window: NSWindow?

    init(monitor: PostureMonitor, overlay: TurtleOverlay, recalibrate: @escaping () -> Void) {
        self.monitor = monitor
        self.overlay = overlay
        self.recalibrate = recalibrate
    }

    // Keeps the current screen when none is given
    func show(_ screen: MainScreen? = nil) {
        if let screen { self.screen = screen }
        if window == nil {
            let root = MainView(main: self, monitor: monitor, overlay: overlay, recalibrate: recalibrate)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.title = "펴부기"
            window.contentMinSize = Self.size
            window.setContentSize(Self.size)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.bringToFront()
    }
}

private struct MainView: View {
    let main: MainWindow
    let monitor: PostureMonitor
    let overlay: TurtleOverlay
    let recalibrate: () -> Void

    var body: some View {
        ZStack {
            Color.main5
            HStack(alignment: .top, spacing: 0) {
                Sidebar(main: main, monitor: monitor)
                    .padding(.vertical, 16)
                    .padding(.leading, 16)
                    .padding(.trailing, 24)
                VStack(alignment: .leading, spacing: 21) {
                    switch main.screen {
                    case .report:
                        ReportScreen(state: .empty)
                    case .settings:
                        SettingsScreen(overlay: overlay, monitor: monitor, recalibrate: recalibrate)
                    }
                }
                .frame(width: main.collapsed ? 1140 : 976)
                .frame(maxHeight: .infinity)
            }
            .frame(width: MainWindow.size.width, height: MainWindow.size.height, alignment: .topLeading)
        }
        .frame(minWidth: MainWindow.size.width, minHeight: MainWindow.size.height)
    }
}

// Tapping an empty part of the sidebar collapses or expands it; the menu and detection buttons only do their own job
private struct Sidebar: View {
    let main: MainWindow
    let monitor: PostureMonitor

    var body: some View {
        let collapsed = main.collapsed
        VStack(alignment: collapsed ? .center : .leading, spacing: 0) {
            VStack(alignment: collapsed ? .center : .leading, spacing: 32) {
                Image(collapsed ? "LogoSymbol" : "Logo")
                    .accessibilityLabel("펴부기")
                VStack(spacing: 8) {
                    tab(.report, "자세 리포트", icon: "NavReport", activeIcon: "NavReportActive")
                    tab(.settings, "설정", icon: "NavSettings", activeIcon: "NavSettingsActive")
                }
                .swallowTaps()
            }
            Spacer(minLength: 0)
            detection
                .swallowTaps()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 36)
        .frame(width: collapsed ? 80 : 240, height: 805)
        .background(Color.main1, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { main.collapsed.toggle() }
    }

    private func tab(_ screen: MainScreen, _ label: String, icon: String, activeIcon: String) -> some View {
        let active = main.screen == screen
        let collapsed = main.collapsed
        return Button {
            main.screen = screen
        } label: {
            HStack(spacing: collapsed ? 16 : 12) {
                Image(active ? activeIcon : icon)
                    .renderingMode(.template)
                    .frame(width: 24, height: 24)
                if !collapsed {
                    Text(label).textStyle(active ? .labelBold : .label)
                    Spacer(minLength: 0)
                }
            }
            .padding(8)
            .frame(width: collapsed ? 48 : nil, height: 48)
            .frame(maxWidth: collapsed ? nil : .infinity)
            .foregroundStyle(Color.grey200)
            .background(active ? Color.main2 : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? label : "")
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var detection: some View {
        if monitor.isDetecting {
            DetectionTimer(monitor: monitor, collapsed: main.collapsed)
        } else {
            Button {
                Task { await monitor.start() }
            } label: {
                HStack(spacing: 4) {
                    if !main.collapsed {
                        Text("자세 감지 시작").textStyle(.labelBold)
                    }
                    Image("IconPlay").renderingMode(.template).foregroundStyle(Color.main1)
                }
                .foregroundStyle(Color.grey900)
                .padding(10)
                .frame(width: main.collapsed ? 44 : nil, height: 44)
                .frame(maxWidth: main.collapsed ? nil : .infinity)
                .background(Color.main5, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(main.collapsed ? "자세 감지 시작" : "")
            .accessibilityLabel("자세 감지 시작")
        }
    }
}

// Pause keeps the elapsed time for the next start, stop clears it. Collapsed, only the pause button is shown
private struct DetectionTimer: View {
    let monitor: PostureMonitor
    let collapsed: Bool

    var body: some View {
        if collapsed {
            pause
        } else {
            HStack {
                pause
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.format(monitor.elapsed(at: context.date)))
                        .textStyle(.heading)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                square("IconStop", label: "종료") { monitor.end() }
            }
        }
    }

    private var pause: some View {
        square("IconPause", label: "일시정지") { monitor.stop() }
    }

    private func square(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .foregroundStyle(Color.main1)
                .frame(width: 44, height: 44)
                .background(Color.main5, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // HH:MM:SS
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

// White card shared by the report and settings screens
struct Card<Content: View>: View {
    var spacing: CGFloat = 24
    var alignment = HorizontalAlignment.leading
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .frame(height: height)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(red: 26 / 255, green: 40 / 255, blue: 46 / 255).opacity(0.05), radius: 8, x: 4, y: 4)
    }
}

private extension View {
    // Keeps taps on this area from reaching the sidebar's collapse gesture
    func swallowTaps() -> some View {
        contentShape(Rectangle()).onTapGesture {}
    }
}
