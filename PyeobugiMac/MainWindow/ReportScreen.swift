import SwiftUI

// Everything the report screen can show. The screen only draws a state; whoever loads the report
// (local events now, the server later) produces it, so the screen never touches storage or the network
enum ReportState {
    case loading
    case empty
    case failed(offline: Bool)
}

struct ReportScreen: View {
    let state: ReportState
    var retry: () -> Void = {}
    var retrying = false

    var body: some View {
        Text("자세 리포트").textStyle(.title).foregroundStyle(Color.grey900)
        switch state {
        case .loading:
            ReportPanel {
                VStack(spacing: 16) {
                    Spinner()
                    Text("기록을 불러오는 중...").textStyle(.heading).foregroundStyle(Color.grey900)
                }
            }
        case .empty:
            ReportPanel {
                Image("ReportEmpty")
                    .resizable()
                    .frame(width: 300, height: 300)
                    .accessibilityHidden(true)
                messages("아직 기록이 없어요", "자세 감지를 시작하고, 펴부기와 함께 기록을 쌓아가봐요!")
            }
        case .failed(let offline):
            ReportPanel {
                // The picture includes the Wi-Fi mark above the character
                Image("ReportError")
                    .resizable()
                    .frame(width: 300, height: 404)
                    .accessibilityHidden(true)
                messages("기록을 불러올 수 없어요",
                         (offline ? "인터넷 연결을 확인한 뒤 다시 시도해 주세요." : "잠시 뒤에 다시 시도해 주세요.")
                             + "\n그동안의 자세 기록은 기기에 저장해 두었다가 연결되면 자동으로 동기화해요.")
                Button(action: retry) {
                    HStack(spacing: 4) {
                        Text("다시 시도")
                        Image("IconRefresh").renderingMode(.template)
                    }
                }
                .buttonStyle(FilledButtonStyle(fill: false))
                .disabled(retrying)
            }
        }
    }

    private func messages(_ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Text(title).textStyle(.heading).foregroundStyle(Color.grey900)
            Text(message).textStyle(.body).foregroundStyle(Color.grey500)
        }
        .multilineTextAlignment(.center)
    }
}

// Card shared by the loading, empty and error states
private struct ReportPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Card(alignment: .center, height: 699) {
            content
        }
    }
}
