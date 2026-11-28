# 펴부기 macOS

웹캠으로 거북목과 고개 숙임을 감지해 바른 자세를 돕는 macOS 앱 (Swift, SwiftUI, Apple Vision).
영상·얼굴·자세 수치는 기기 밖으로 나가지 않고, 서버로는 익명 이벤트 로그만 보냅니다.

## 시작하기

처음 클론했다면 커밋 차단 훅부터 설치하세요.

```bash
git config core.hooksPath .githooks
chmod +x .githooks/*
```

전체 세팅은 [docs/setup.md](docs/setup.md)를 참고하세요.

시작 화면 글꼴은 Pretendard(SIL Open Font License 1.1)이며, 라이선스 전문은 [ThirdPartyLicenses/](ThirdPartyLicenses/)에 있고 앱 번들에도 함께 들어갑니다.

## 브랜치

| 브랜치 | 용도 |
| --- | --- |
| `main` | 직접 커밋·푸시 금지, PR로만 머지 |
| `feature/*`, `fix/*`, `docs/*`, `chore/*` | `main`에서 분기, `main`으로 PR |

GitHub Flow를 따릅니다. 릴리스는 `main`에 `vX.Y.Z` 태그로 표시합니다.

## 문서

| 문서 | 내용 |
| --- | --- |
| [docs/setup.md](docs/setup.md) | 저장소·Xcode 세팅, 로컬 서버 |
| [docs/architecture.md](docs/architecture.md) | 구조, 기능별 구현 |
| [docs/detection.md](docs/detection.md) | Vision 감지, 점수식, 판정 로직 |
| [docs/backend-integration.md](docs/backend-integration.md) | API, 이벤트, 인코딩 규칙 |
| [docs/roadmap.md](docs/roadmap.md) | 작업 순서, 미결정 사항 |
