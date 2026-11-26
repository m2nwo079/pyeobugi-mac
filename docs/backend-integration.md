# 서버 연동

서버로는 익명 이벤트만 보낸다. 운영 서버 API 문서(Swagger): https://pyeobugi-server-production.up.railway.app

## 엔드포인트

| 메서드 | 경로 | 내용 |
| --- | --- | --- |
| `POST` | `/api/devices/register` | 기기 등록, `deviceSecret` 발급 (기기 ID당 1회). 헤더는 `X-Device-Id`만 |
| `POST` | `/api/events` | 이벤트 배치 저장. 1~100개, 본문 64KB 이하 |
| `GET` | `/api/reports/summary` | 리포트. `?date=YYYY-MM-DD` 선택 (생략 시 오늘) |

인증: `X-Device-Id`(UUID v4) + `X-Device-Secret`. 로그인 없음.

## 이벤트

공통 필드: `eventId`(UUID v4), `sessionId`(UUID v4), `occurredAt`(KST 시각), `type`, `payload`

| type | payload |
| --- | --- |
| `SESSION_START` | `{}` |
| `SESSION_END` | `{}` |
| `USAGE_SEGMENT` | `startedAt`, `endedAt`, `durationSec`(0~3600), `badDurationSec`, `mildDurationSec`(선택) |
| `POSTURE_BAD` | `severity`: `MILD` / `MODERATE` / `SEVERE` |
| `POMODORO_COMPLETED` | `{}` |
| `CALIBRATION_COMPLETED` | `isRecalibration`: Bool |
| `BUBBLE_SHOWN` | `bubbleType`: `POSTURE` / `STRETCH` / `TIMER_BREAK` / `ENCOURAGE` / `GREETING` |
| `SETTINGS_CHANGED` | `studyTimer`, `stretch`, `awayPause`, `overlay`: Bool |

`USAGE_SEGMENT` 규칙: `badDurationSec ≤ durationSec`, `mildDurationSec ≤ badDurationSec`, `startedAt < endedAt`, 시작과 끝이 같은 KST 날짜.
세부 규칙은 서버 검증을 기준으로 한다.

## 인코딩 주의 사항

- **정의되지 않은 필드는 거부된다** (화이트리스트, `FORBIDDEN_FIELD`). 모델에 필드를 임의로 추가하지 않는다.
- **시각은 `+09:00` 오프셋, 초 단위까지만**: `2026-11-26T14:03:00+09:00`. `Z`, 다른 오프셋, 밀리초는 `INVALID_PAYLOAD`.
  `JSONEncoder`의 기본 날짜 전략은 쓰지 않고, 시각을 미리 문자열로 만들어 담는다.
- **선택 필드는 `null`이 아니라 키를 생략한다**. Swift 옵셔널은 합성된 `Codable`에서 `nil`이면 키가 빠지므로 그대로 쓰면 된다.
  커스텀 `encode(to:)`를 쓸 때는 `encodeIfPresent`를 쓴다.
- 응답 에러 본문은 `{ code, message?, traceId?, retryAfter? }`. 클라이언트는 `code`만 필수로 본다.
- `POST /api/events` 응답은 `accepted`(개수)와 `rejected`(인덱스와 사유: `INVALID_PAYLOAD`, `FORBIDDEN_FIELD`, `UNKNOWN_TYPE`, `OCCURRED_AT_OUT_OF_RANGE`).

```swift
enum KST {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        // Seconds precision with a fixed +09:00 offset, as the server requires
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
```

## 기기 정보 저장

- `deviceId`: 첫 실행 시 UUID v4 생성 후 저장
- `deviceSecret`: 등록 응답으로 받은 값. **키체인에 저장**
- 등록 실패 시 이벤트는 큐에 쌓아 두고 나중에 재시도한다.

## 이벤트 큐

- 오프라인이어도 이벤트를 잃지 않도록 Application Support 아래 파일로 저장한다 (원자적 쓰기).
- 한 번에 최대 100개, 64KB 이하로 나눠 보낸다.
- `retryAfter`가 오면 그 시간 뒤에 재시도한다.
- 응답을 받으면 accepted, 중복, `rejected` 모두 큐에서 뺀다. 거부된 이벤트는 재시도 없이 폐기한다.
  서버는 같은 `eventId`를 중복 저장하지 않으므로 응답을 못 받은 배치는 그대로 다시 보내도 된다.

## 개발 서버

- Debug 빌드: `http://localhost:8080/api` (로컬 서버, `docs/setup.md` 6번)
- Release 빌드: 운영 서버
- 운영 서버에 테스트 데이터를 보내지 않는다.
