# 구조

## 데이터 흐름

```
Camera (AVCaptureSession)
  → Vision (VNDetectFaceRectanglesRequest rev3): pitch, boundingBox.height
  → PostureCore: smoothing → score → engine state machine → feedback
  → App: overlay, menu bar, bubbles, usage tracking
  → PyeobugiAPI: anonymous events → queue → POST /api/events
```

pitch·얼굴 크기·기준값은 `PostureCore`와 앱 안에서만 쓰이고 `PyeobugiAPI`로 넘어가지 않는다.

## 모듈

| 모듈 | 내용 | 의존 |
| --- | --- | --- |
| `PyeobugiMac` (앱) | SwiftUI 화면, 메뉴 막대, 오버레이, 카메라, Vision | `PostureCore`, `PyeobugiAPI` |
| `PostureCore` | 점수, 상태 기계, 평활, 기준 잡기, 거리 변화 | 없음 (Foundation만) |
| `PyeobugiAPI` | `Codable` 이벤트, 기기 등록, 이벤트 큐, 리포트 조회 | Foundation |

## 기능별 구현

| 기능 | 구현 |
| --- | --- |
| 카메라 + 얼굴 감지 | AVFoundation + Vision |
| 거북이 오버레이 | `NSPanel` (borderless, nonactivating, 클릭 통과, 모든 Space) + SwiftUI 도형, `TimelineView` 애니메이션. 동작과 상수는 `docs/overlay.md` |
| 거북이 표시 토글 | 메뉴 `Toggle`, `UserDefaults` 키 `showTurtle` (기본 켜짐) |
| 메뉴 막대 | SwiftUI `MenuBarExtra`, 템플릿 이미지 아이콘 |
| 앱 창 (온보딩·리포트·설정) | SwiftUI `Window` |
| 리포트 차트 | Swift Charts |
| 설정 | `UserDefaults` / `@AppStorage` |
| `deviceSecret` | 키체인 |
| 이벤트 큐 | `PyeobugiAPI` (`Codable` + 파일 기반 큐) |
| 로그인 시 실행 | `SMAppService.mainApp` |

## 오버레이 기본 설정

```swift
let panel = NSPanel(
    contentRect: screen.visibleFrame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
// Let clicks pass through to the apps underneath
panel.ignoresMouseEvents = true
panel.level = .statusBar
// Show on every Space and over full-screen apps
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```

`visibleFrame`은 메뉴 막대와 Dock을 뺀 영역.

## 동시성

- 앱 타깃의 기본 액터 격리는 `MainActor`.
- `AVCaptureVideoDataOutputSampleBufferDelegate`는 캡처 큐에서 불리므로 `nonisolated`로 표시하고, Vision 처리까지 그 큐에서 한 뒤
  결과만 메인 액터로 넘긴다.

```swift
nonisolated func captureOutput(_ output: AVCaptureOutput,
                               didOutput sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
    // Runs on the capture queue; only Vision work happens here
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let sample = Self.detectFace(in: pixelBuffer)
    Task { @MainActor in
        // Hand the result to main-actor state
        self.ingest(sample)
    }
}
```

- 프레임 카운터처럼 캡처 큐에서 바뀌는 상태는 두지 않는다. 적응형 주기는 "마지막 감지 시각 + 다음 간격"으로 판단한다.
