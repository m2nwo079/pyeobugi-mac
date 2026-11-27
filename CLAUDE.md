# 펴부기 macOS (pyeobugi-mac)

웹캠으로 거북목·고개 숙임을 감지해 바른 자세를 돕는 macOS 네이티브 앱 (Swift, SwiftUI, Apple Vision).

## 절대 규칙

1. **`main` 브랜치에 직접 커밋하거나 푸시하지 않는다.** 예외 없음.
   - 커밋 전 `git branch --show-current`로 현재 브랜치를 확인한다. `main`이면 작업을 멈추고 브랜치부터 만든다.
   - `main`은 작업 브랜치에서 올린 Pull Request로만 갱신한다.
   - `.githooks/`의 pre-commit, pre-merge-commit, pre-push 훅이 이를 막는다. `--no-verify`로 우회하지 않는다.
2. 영상, 얼굴 이미지, 랜드마크, pitch, 얼굴 크기, 개인 기준값은 기기 밖으로 보내지 않는다. 서버에는 익명 이벤트만 보낸다.
3. `Packages/PostureCore`의 판정 로직(점수식, 상수, 상태 기계)은 `docs/detection.md`가 명세다.
   임의로 상수를 바꾸지 않는다. 바꾸면 명세, 테스트, 상수 변경 기록을 함께 갱신한다.

## 브랜치와 커밋

| 브랜치 | 용도 |
| --- | --- |
| `main` | 항상 빌드·실행 가능한 상태. PR로만 머지 |
| `feature/*`, `fix/*`, `docs/*`, `chore/*` | 최신 `main`에서 분기, `main`으로 PR |

- GitHub Flow를 따른다. `dev` 같은 장기 통합 브랜치는 두지 않는다.
- 작업 브랜치는 짧게 유지하고, 머지 후 삭제한다.
- 릴리스는 `main`의 커밋에 `vX.Y.Z` 태그를 붙여 표시한다.

- 커밋 메시지는 Conventional Commits, 영어: `feat: add adaptive detection interval`
  - 타입: `feat` `fix` `refactor` `perf` `test` `docs` `chore` `build` `ci`
- 여러 파일을 고쳤더라도 성격이 다르면 커밋을 나눈다 (예: 로직 이식과 UI 변경은 별도 커밋).

## 코드 규칙

- 코드 안의 모든 텍스트(주석, 로그, 식별자)는 영어. 사용자에게 보이는 UI 문자열만 한국어.
- 주석은 코드와 같은 줄에 쓰지 않고 항상 윗줄에 따로 쓴다.
- 앱 타깃은 기본 액터 격리가 `MainActor`다. 카메라 델리게이트처럼 다른 큐에서 불리는 코드는 `nonisolated`로 표시하고,
  결과는 `Task { @MainActor in ... }`로 넘긴다.
- `PostureCore`는 UI·AVFoundation·Vision을 import하지 않는 순수 Swift로 유지한다 (값 타입, `Sendable`).

## 구조

```
PyeobugiMac/            app target: SwiftUI, menu bar, windows
  Capture/              AVCaptureSession + Vision (pitch, face size)
  Overlay/              NSPanel turtle overlay
Packages/
  PostureCore/          posture scoring, engine, calibration, distance
  PyeobugiAPI/          Codable events, device registration, event queue
Config/                 Debug/Release xcconfig (API_BASE_URL)
docs/                   design notes and decisions
```

## 빌드와 실행

- Xcode에서 `PyeobugiMac` 스킴 실행. 로직 테스트는 `cd Packages/PostureCore && swift test`.
- Debug는 `http://localhost:8080/api`(로컬 서버), Release는 운영 서버를 쓴다 (`Config/*.xcconfig`).
- 로컬 서버 실행 방법과 초기 세팅은 `docs/setup.md` 참고.

## 문서 위치

- `docs/setup.md`: 새 저장소 세팅, Xcode 프로젝트 설정, 훅 설치, 로컬 서버
- `docs/architecture.md`: 데이터 흐름, 모듈 구조, 기능별 구현
- `docs/detection.md`: Vision 감지, 점수식, 시간 상수, 상수 변경 기록
- `docs/overlay.md`: 거북이 오버레이 동작, 동작 상수(크기, 속도, 확률, 대기·전환 시간)
- `docs/backend-integration.md`: API, 이벤트 종류, 인코딩 규칙
- `docs/roadmap.md`: 작업 순서와 미결정 사항
