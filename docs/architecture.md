# 구조

## 데이터 흐름

```
Camera (AVCaptureSession)
  → Vision (VNDetectFaceRectanglesRequest rev3): pitch, boundingBox.height
  → PostureCore: smoothing → score → engine state machine → feedback
  → App: overlay, menu bar, main window (report, settings), bubbles
  → EventRecorder → PyeobugiAPI: anonymous events, usage segments → EventStore (local files)
  → later: unsent events → POST /api/events
```

pitch·얼굴 크기·기준값은 `PostureCore`와 앱 안에서만 쓰이고 `PyeobugiAPI`로 넘어가지 않는다.

## 모듈

| 모듈 | 내용 | 의존 |
| --- | --- | --- |
| `PyeobugiMac` (앱) | SwiftUI 화면, 메뉴 막대, 오버레이, 카메라, Vision | `PostureCore`, `PyeobugiAPI` |
| `PostureCore` | 점수, 상태 기계, 평활, 기준 잡기, 거리 변화 | 없음 (Foundation만) |
| `PyeobugiAPI` | `Codable` 이벤트, KST 시각, 사용 구간, 이벤트 저장소. 기기 등록·전송·리포트 조회는 서버 연동 단계 | Foundation |

## 기능별 구현

| 기능 | 구현 |
| --- | --- |
| 카메라 + 얼굴 감지 | AVFoundation + Vision |
| 카메라 열기와 감지 분리 | `openCamera`는 카메라만 연다. 감지(`isDetecting`) 중이 아니면 엔진·피드백을 갱신하지 않고 기준 잡기 샘플만 모은다. 기준 잡기 창을 닫으면 감지 중이 아닐 때 카메라도 끈다. 창을 닫은 뒤에 카메라 열기가 끝나도 감지 중이 아니면 바로 끈다 |
| 온보딩·기준 잡기 창 | `NSWindow` + `NSHostingController`, 1280×832 고정. 시작 → 권한 → 기준 잡기 → 완료 안내 후 창을 닫고 메인 창의 리포트 화면을 연다. 메뉴의 "기준 잡기"와 설정 화면의 "기준 다시 잡기"는 기준 잡기 화면만 띄우고, 끝나도 메인 창을 열지 않는다. 완료 여부는 `UserDefaults` 키 `onboarded`(기준을 저장할 때 기록) |
| 온보딩 시작 화면 | `NSViewRepresentable`(`IntroScreen`)로 감싼 `IntroView`. 1280×832 무대를 창을 덮도록 맞추고, 정적 그림(배경·노트북·화면 광택)은 2배 PNG, 거북이 부위는 4배 PNG, 로고는 벡터 SVG, 글자는 Core Text(Pretendard 번들)로 그린다. 디스플레이 링크가 가상 시계(`IntroClock`)를 옮기고 레이어 변형만 바꾼다. 창을 닫거나 권한 화면으로 넘어가면 디스플레이 링크와 포인터 추적을 멈춘다. 동작과 상수는 `docs/intro.md` |
| 기준 잡기 미리보기 | 감지와 같은 `AVCaptureSession`에 `AVCaptureVideoPreviewLayer`(거울 모드)를 붙인다. 프레임은 저장하지 않는다. 미리보기가 켜진 동안에는 감지 주기와 별개로 프레임마다 얼굴 영역과 눈·코·입 중심(`VNDetectFaceLandmarksRequest`)을 구한다. 네모와 각 점은 시상수 `previewSmoothingTime`(0.15초)의 시간 기반 지수 평활로 따라가고, 얼굴을 놓친 프레임은 `previewHoldTime`(0.3초) 동안 마지막 표시를 유지한다(`PostureMonitor`). pitch를 얻으면(같은 0.3초 유지 포함) "기준 잡기" 버튼이 나온다. 수집이 시작되면 얼굴을 놓쳐도 화면과 버튼이 유지되고, 버튼은 수집이 끝날 때까지 비활성이다 |
| 기준 잡기 진행 표시 | 수집 중에는 버튼 대신 남은 초(`CalibrationRun` 판정의 `remainingSeconds`)와 진행 막대를 보여 준다. 움직여서 실패하면 실패 문구와 "다시 시도" 버튼을 보여 주고, 새 시도가 시작되면 실패 표시를 지운다 |
| 기준 잡기 진단 로그 | `os.Logger` debug, 카테고리 `calibration`. 시작 호출, 샘플 수, 얼굴 유무, 판정 결과와 실패 사유만 남기고 pitch·크기·좌표는 남기지 않는다 |
| 거북이 오버레이 | `NSPanel` (borderless, nonactivating, 클릭 통과, 모든 Space, 토글에 따라 전체 화면 Space 포함) + 부위별 Core Animation 레이어(`TurtleView`), 디스플레이 링크로 프레임 수 조절. 동작과 상수는 `docs/overlay.md` |
| 거북이 잡기·던지기 | 포인터가 거북이(또는 누를 수 있는 말풍선) 위에 있을 때만 `ignoresMouseEvents`를 끈다 (`TurtlePointer`). 클릭이 통과하는 동안은 마우스 이동 전역 모니터(추가 권한 없음), 받는 동안은 뷰 추적 영역과 마우스 이벤트로 포인터를 얻는다. 받거나 끄는 동안만 도는 디스플레이 링크가 프레임마다 거북이 밖·버튼 떼어짐을 확인해 클릭 통과로 되돌린다. 물리(`TurtleFlight`)는 그리기 디스플레이 링크 프레임마다 한 단계 |
| 거북이 표시 토글 | 메뉴 `Toggle`과 설정 화면 "거북이 오버레이 표시", `UserDefaults` 키 `showTurtle` (기본 켜짐) |
| 오버레이 표시 조건 | `TurtleOverlay.apply()` 한 곳에서 정한다. 온보딩(`onboarded`)이 끝나기 전에는 거북이·타이머 패널을 띄우지 않고, 기준을 저장하면 `PostureMonitor.onBaselineSaved`로 다시 판단한다. 전체 화면 Space에 띄울지는 "전체 화면에서도 표시" 토글(`UserDefaults` 키 `showOverFullScreen`, 기본 켜짐)이 `collectionBehavior`의 `.fullScreenAuxiliary`로 정하고, 바꾸면 열린 두 패널에 바로 적용한다. 꺼져 있으면 시스템이 그 Space에서 패널을 그리지 않을 뿐 패널은 닫지 않는다. 조건은 `docs/overlay.md` 띄우는 조건 |
| 말풍선 | `PostureCore`의 `BubblePicker`가 고르고, `TurtleBubbles`가 오버레이 갱신 루프에서 트리거를 넣는다. SwiftUI 뷰를 `NSHostingView`로 패널 컨테이너에 붙이고, `TurtleView`가 그린 프레임마다 머리 위로 옮긴다. 거리 말풍선은 `TurtlePointer`의 `tapArea`로 클릭을 받아 기준 잡기 창을 연다. 동작과 상수는 `docs/overlay.md` |
| 앉은 거리 변화 | `PostureMonitor`가 감지 중 샘플마다 `stepDistance`로 갱신하고, 감지를 멈추면 초기화한다 |
| 공부 타이머 | `PostureCore`의 `Pomodoro`를 `StudyTimer`가 1초마다 진행한다. 설정 화면 토글, `UserDefaults` 키 `studyTimer` (기본 꺼짐). 거북이를 꺼 두면 오른쪽 아래 작은 패널(`TimerCorner`)에 남은 시간만 띄운다 |
| 스트레칭 알림 | 설정 화면 토글, `UserDefaults` 키 `stretchReminder` (기본 켜짐) |
| Debug 짧은 시간 | Debug 빌드에서 실행 인자 `-fastTimers YES`면 분 단위 시간을 60분의 1로 (`FastTimers`) |
| 교정 강도 | 설정 화면 3단 슬라이더(느슨하게·보통·엄격하게), `UserDefaults` 키 `sensitivity`(`Sensitivity.rawValue`, 기본 보통). `TurtleOverlay`가 `PostureMonitor.sensitivity`에 넘겨 판정 각도(진입 느슨 15°·보통 10°·엄격 6.5°)를 바꾸고, 목이 늘어나기 시작하는 지연도 바꾼다. 나쁜 자세 확정 시간은 그대로다 (`docs/detection.md` 교정 강도별 판정 각도, 펫 표시 상수) |
| 반응 시간 로그 | `os.Logger` debug, 범주 `posture`. 후보 시작, 확정, 목 요청, 목 늘어남 시작, 회복 시각만 `FaceCapture.now()` 기준으로 남긴다. pitch·크기·점수는 남기지 않는다 (`docs/detection.md` 반응 지연) |
| 메뉴 막대 | SwiftUI `MenuBarExtra`, 템플릿 이미지 아이콘. 메뉴: 상태, 카메라 권한 안내, 기준 잡기 진행 문구, 감지 시작·정지, 펴부기 열기, 기준 잡기, 거북이 표시, 종료. 나머지 설정은 설정 화면에만 둔다 |
| 메인 창 (리포트·설정) | `NSWindow` + `NSHostingController`(`MainWindow`), 1280×832 고정 레이아웃을 가운데에 둔다. 사이드바로 화면을 바꾸고 감지를 시작·일시정지·종료한다. 실행 시(온보딩 완료 상태), 온보딩 완료, 메뉴 "펴부기 열기", 실행 중 재실행(`applicationShouldHandleReopen`)에서 연다. 리포트 화면은 `ReportState`만 받아 그린다. 상수는 `docs/app-window.md` |
| 리포트 차트 | Swift Charts |
| Dock 아이콘 | 제목 막대가 있는 창(메인, 온보딩·기준 잡기)이 열려 있는 동안만 activation policy `.regular`로 Dock과 Cmd+Tab에 보이고, 마지막 창이 닫히면(`NSWindow.willCloseNotification`) `.accessory`로 메뉴 막대 전용이 된다. Dock으로 내린 창도 열린 창으로 센다. 오버레이 패널은 제목 막대가 없어 세지 않는다. `LSUIElement`는 쓰지 않으므로 실행 직후에는 `.regular`이고, 실행할 때 항상 창을 연다. 창은 `NSWindow.bringToFront()`로 정책을 `.regular`로 바꾼 뒤 키 창으로 만들고 앱을 활성화한다. Dock 아이콘 클릭과 재실행(`applicationShouldHandleReopen`)은 열린 창 중 맨 앞 창을 앞으로 가져오고, 열린 창이 없으면 메인 창을 연다 (`AppDelegate`) |
| 설정 | `UserDefaults`. 메뉴·설정 화면·오버레이가 같은 `TurtleOverlay` 인스턴스의 속성을 쓴다 |
| `deviceSecret` | 키체인 |
| 이벤트 기록 | 앱의 `EventRecorder`가 세션·사용 구간·나쁜 자세·기준 잡기·말풍선·집중 완료·설정 변경을 이벤트로 만들어 `EventStore` 프로토콜에 넘긴다. 저장은 `PyeobugiAPI`의 `FileEventStore`(KST 날짜별 JSON, 원자적 쓰기, 90일 보관, 하루 5,000개). 규칙은 `docs/events.md` |
| 감지 시작 실행 인자 | `-startDetection YES`면 온보딩을 마친 상태에서 실행 직후 감지를 시작한다. 실행 인자에서만 읽어 `UserDefaults`에 남지 않는다 (측정용) |
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
// Mouse moves reach the view while the pointer is over the turtle and events are taken
panel.acceptsMouseMovedEvents = true
panel.level = .statusBar
// Every Space; another app's full-screen Space only while "show over full screen" is on
panel.collectionBehavior = overFullScreen
    ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    : [.canJoinAllSpaces, .stationary]
```

`visibleFrame`은 메뉴 막대와 Dock을 뺀 영역.
`ignoresMouseEvents`는 포인터가 거북이나 누를 수 있는 말풍선 위에 있는 동안만 `false`가 된다 (`docs/overlay.md` 포인터와 클릭 통과).
패널 내용 뷰는 빈 컨테이너이고, 그 안에 `TurtleView`와 말풍선 뷰를 나란히 둔다.

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
