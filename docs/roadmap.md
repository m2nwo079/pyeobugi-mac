# 작업 순서와 미결정 사항

## 작업 순서

1. **저장소 세팅**: `docs/setup.md` 1~4번 (훅, Xcode 프로젝트, 패키지)
2. **Vision 검증 기록**: 라벨별 기록을 모아 현재 상수가 Vision pitch에서도 맞는지 확인
   - 라벨: 바른 자세 / 거북목(머리 내밀기) / 고개 숙임 / 필기·자료 보기
   - 조명·거리를 바꿔 라벨당 2~3회
   - 기록에는 pitch·크기·시각만 저장, 영상 저장 금지 (`recordings/`는 gitignore)
   - 라벨별 오탐률·검출률로 비교한다
3. **`PostureCore` 이식**: score → engine → calibration → distance → feedback 순, 테스트와 함께
4. **최소 앱**: 카메라 + Vision + 엔진 연결, 메뉴 막대에 상태만 표시
5. **온보딩**: 카메라 권한, 기준 잡기, 기준값 저장
   - 기준 잡기 중 카메라 미리보기 표시
6. **거북이 오버레이**
7. **`PyeobugiAPI`**: 기기 등록, 이벤트 큐, 전송 (로컬 서버로 확인)
8. **리포트 화면**: `GET /api/reports/summary`, Swift Charts
9. **뽀모도로, 말풍선, 스트레칭 알림, 로그인 시 실행**
10. **배포**: 서명, 공증, dmg, CI(GitHub Actions macOS 러너)

## 미결정 사항

| 항목 | 선택지 | 메모 |
| --- | --- | --- |
| 최소 macOS | 13 / 14 / 15 | `MenuBarExtra`·Swift Charts 13+, SwiftData·`@Observable` 14+. |
| Bundle ID | `com.pyeobugi.PyeobugiMac` 등 | |
| Dock 아이콘 | 표시 / 숨김(메뉴 막대 전용) | 숨기면 `LSUIElement`, Cmd+Tab 목록에서 빠짐 |
| 배포 채널 | Developer ID 직접 배포 / Mac App Store | 둘 다 Apple Developer Program(유료) 필요. App Store는 샌드박스 필수 |
| 서명 | Developer ID / ad-hoc | ad-hoc은 빌드마다 카메라 권한을 다시 요청할 수 있음 |

## 확인이 필요한 것 (미검증)

- Vision pitch의 잡음 수준과 범위가 기존 임계값에 맞는지 (2번에서 확인)
- App Nap이 백그라운드 감지 주기에 영향을 주는지
- 다른 앱(화상회의 등)과 카메라 동시 사용 시 동작
