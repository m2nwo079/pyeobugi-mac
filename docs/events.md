# 로컬 이벤트

기기 안에 익명 이벤트를 기록한다. 지금은 로컬 리포트가 읽고, 서버 연동 단계에서는 같은 이벤트를 그대로 `POST /api/events`로 보낸다.
이벤트 형식과 인코딩 규칙은 `docs/backend-integration.md`를 따른다.

## 구조

- `PyeobugiAPI`
  - `KST`: `+09:00` 초 단위 문자열, KST 날짜, 다음 자정
  - `Event`, `EventPayload`: 서버 형식 그대로 인코딩 (소문자 UUID, KST 문자열, 선택 필드는 키 생략)
  - `UsageTracker`: 감지 샘플로 사용 구간을 만든다
  - `EventStore` 프로토콜과 `FileEventStore`
- 앱의 `EventRecorder`: 앱 동작을 이벤트로 바꿔 `EventStore`에 넘긴다. 저장소 구현은 `openDefault()` 한 곳에서만 고른다
- 이벤트에는 pitch, 얼굴 크기, 기준값, 교정 강도가 들어가지 않는다. 모델에 그런 필드가 없다

## 이벤트를 만드는 규칙

- `sessionId`: 앱 실행마다 새 UUID v4. 실행 1회가 세션 1개이고, 잠자기로 세션을 끝내지 않는다
- `eventId`: 이벤트를 만들 때 새 UUID v4 (서버 중복 방지 키)

| type | 기록 시점 |
| --- | --- |
| `SESSION_START` | 앱 실행 |
| `SESSION_END` | 정상 종료 (`applicationWillTerminate`) |
| `USAGE_SEGMENT` | 사용 구간이 끊길 때 |
| `POSTURE_BAD` | 나쁜 자세 확정 (`.badEnter`) |
| `POMODORO_COMPLETED` | 집중 시간 끝 (`focusCompleted`) |
| `CALIBRATION_COMPLETED` | 기준 저장 |
| `BUBBLE_SHOWN` | 말풍선이 새로 뜰 때 |
| `SETTINGS_CHANGED` | 기능 토글 변경 |

- `SESSION_END` 전에 열린 사용 구간을 먼저 마감한다
- `POSTURE_BAD`의 `occurredAt`은 확정 시각이 아니라 나쁜 자세가 시작된 시각이다 (캡처 단조 시계를 벽시계로 바꾼다)
- `CALIBRATION_COMPLETED`의 `isRecalibration`은 기준을 저장하기 직전에 온보딩을 마친 상태였는지
- `BUBBLE_SHOWN`: 거리 말풍선은 전용 타입이 없어 `POSTURE`로 기록한다
- `SETTINGS_CHANGED`
  - 보내는 값은 거북이 표시(`overlay`), 공부 타이머(`studyTimer`), 스트레칭 알림(`stretch`), 자리비움(`awayPause`)뿐이다
  - 자리비움 설정이 아직 없어 `awayPause`는 항상 `false`
  - 0.5초 안의 변경은 하나로 묶고, 마지막으로 기록한 값과 같으면 기록하지 않는다. 실행할 때의 값은 이미 기록한 것으로 본다

## 사용 구간 (`UsageTracker`)

시간 상수는 `UsageTiming`에 있다.

| 상수 | 값 | 뜻 |
| --- | --- | --- |
| `segment` | 60초 | 구간을 끊는 간격 |
| `away` | 30초 | 얼굴이 이만큼 안 보이면 자리비움 |
| `maxGap` | 5초 | 샘플 간격이 이보다 길면 그 사이는 세지 않음 |
| `checkpoint` | 10초 | 열린 구간 스냅샷 저장 간격 |

- 감지 중 샘플마다 갱신한다. 나쁜 자세 시간은 `phase == .bad`인 동안, 살짝 숙임 시간은 그중 `severity == .mild`인 동안 센다
- 이어지는 구간은 앞 구간이 끝난 시각에서 시작한다 (겹치지 않음)
- 얼굴이 잠깐 안 보이는 시간은 사용 시간에 넣고 나쁜 자세에는 넣지 않는다.
  30초를 넘으면 얼굴이 사라진 시점에서 구간을 끊고 그 뒤는 세지 않는다
- KST 자정에서 끊는다. 마감할 때 자정을 넘었으면 나쁜 자세 시간을 길이에 비례해 나눈다
- `mildDurationSec`는 0이어도 항상 넣는다. `mild ≤ bad ≤ duration`으로 맞춘다
- 감지를 멈추거나 끝낼 때, 잠들기 직전, 앱을 정상 종료할 때 열린 구간을 마감한다

### 잠자기

- 잠든 동안에는 샘플이 오지 않는다. 깨어난 뒤 첫 샘플의 간격이 `maxGap`을 넘으므로 마지막 샘플 시점에서 끊는다
- 마감 시각은 `마지막 샘플 + maxGap`을 넘지 않는다. 깨어난 직후 새 샘플 없이 감지를 멈춰도 잠든 시간이 들어가지 않는다
- 잠들기 직전(`NSWorkspace.willSleepNotification`)에 열린 구간을 마감해 저장한다. 잠든 동안 전원이 꺼져도 구간이 남는다

### 비정상 종료 (강제 종료, 전원 꺼짐)

- 감지 중 `checkpoint`마다, 그리고 구간이 끊길 때마다 열린 구간의 스냅샷을 `pending.json`에 저장한다.
  스냅샷은 얼굴을 마지막으로 본 시점까지만 센다
- 다음 실행 때 저장소를 열면 스냅샷을 일반 이벤트로 옮기고 `pending.json`을 지운다.
  같은 세션·같은 `startedAt`의 구간이 이미 저장돼 있으면 중복으로 보고 버린다
- 잃는 사용 시간은 설계상 최대 `checkpoint`(10초) 정도다
- `SESSION_END`가 없는 세션은 비정상 종료로 본다. 종료 시각을 알 수 없으므로 `SESSION_END`를 만들어 넣지 않는다

## 저장 (`FileEventStore`)

- 위치: 앱의 Application Support 아래 `Events/`. 샌드박스 앱이라 실제 경로는
  `~/Library/Containers/<bundle id>/Data/Library/Application Support/Events/`
- KST 리포트 날짜마다 파일 하나: `2026-11-28.json`
  ```json
  [{"event": {"eventId": "…", "sessionId": "…", "occurredAt": "2026-11-28T10:00:00+09:00", "type": "SESSION_START", "payload": {}}, "sent": false}]
  ```
- 리포트 날짜(`Event.reportDay`): `USAGE_SEGMENT`는 `startedAt`의 날짜, 나머지는 `occurredAt`의 날짜.
  자정에 끝나는 구간은 시작한 날에 들어간다
- 쓸 때마다 그날 파일 전체를 원자적으로 바꾼다 (`Data.write(options: .atomic)`)
- `sent`: 서버 전송 상태 자리. 지금은 항상 `false`이고, 안 보낸 이벤트를 꺼내고 표시하는 메서드는 서버 연동 단계에서 만든다
- 디코딩할 수 없는 날짜 파일은 `<날짜>.json.corrupt`로 옮기고 그날 기록을 새로 시작한다
- 저장소를 열지 못하면 로그만 남기고 기록 없이 앱은 동작한다

### 보관 기간과 상한

- 보관: 오늘을 포함해 90개 KST 날짜. 저장소를 열 때(앱 실행 시) 그보다 오래된 날짜 파일을 지운다. 날짜 형식이 아닌 파일은 건드리지 않는다
- 하루 상한: 리포트 날짜당 5,000개
  - 상한에 닿으면 새 이벤트를 저장하지 않고 버린다 (`EventStoreError.dayFull`). 이미 저장된 이벤트는 그대로 둔다
  - 그날 처음 상한에 닿았을 때 오류 로그를 한 번 남긴다
  - 복구하는 스냅샷도 같은 상한을 따른다
- 24시간 내내 감지해도 사용 구간은 하루 1,440개다

## 리포트 조회

`EventStore.events(from:through:)`로 KST 날짜 범위(`YYYY-MM-DD`, 양 끝 포함)의 이벤트를 저장 순서대로 받는다.
오늘은 `from`과 `through`를 같은 날로, 이번 주는 월요일부터 오늘까지로 조회한다.

## 기기 ID (서버 연동 단계에서 만든다)

- 이벤트 본문에는 기기 ID가 들어가지 않는다. 등록과 전송의 `X-Device-Id` 헤더에만 쓴다
- 첫 실행 때 UUID v4를 소문자로 만들어 `UserDefaults`에 저장하고 계속 쓴다
- `deviceSecret`은 등록 응답으로 받아 키체인에 저장한다 (`docs/backend-integration.md`)

## 확인 방법

- 저장 파일 열기: `open ~/Library/Containers/<bundle id>/Data/Library/Application\ Support/Events`
- 내용 보기: `python3 -m json.tool <날짜>.json`
- 로그: `log stream --predicate 'subsystem == "<bundle id>" AND category == "events"' --level debug`
  (기록한 이벤트 종류와 실패만 남고, 이벤트 내용은 남지 않는다)
- 로직 테스트: `cd Packages/PyeobugiAPI && swift test`
