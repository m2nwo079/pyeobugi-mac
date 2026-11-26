# 감지

## 엔진: Apple Vision

- `VNDetectFaceRectanglesRequest`, `revision = VNDetectFaceRectanglesRequestRevision3` (pitch는 macOS 12부터 제공)
- 입력 신호 두 가지
  - `pitch`: `VNFaceObservation.pitch` (라디안 → 도 변환)
  - `size`: `boundingBox.height` (0~1 정규화)

```swift
let request = VNDetectFaceRectanglesRequest()
// Revision 3 is required for pitch
request.revision = VNDetectFaceRectanglesRequestRevision3
let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
try handler.perform([request])
if let face = request.results?.first, let pitch = face.pitch {
    // Vision reports radians
    let pitchDeg = pitch.doubleValue * 180 / .pi
    let size = face.boundingBox.height
}
```

## 점수식

| 상수 | 값 |
| --- | --- |
| pitch 데드존 | 1.5° |
| pitch 가중치 | 1.4 |
| 크기 가중치 | 120 |
| 크기 게이트 | 기준 대비 pitch 6° 초과부터, 5° 구간에 걸쳐 0→1 |
| 점수 데드존 | 4 |
| 나쁜 자세 진입 / 회복 | 3 / 2 |
| 심각도 | 10 미만 MILD, 18 미만 MODERATE, 그 이상 SEVERE |

```
dPitch   = pitch - baseline.pitch
pitchTerm = dPitch > 1.5 ? (dPitch - 1.5) * 1.4 : 0
gate     = dPitch > 6 ? min(1, (dPitch - 6) / 5) : 0
sizeTerm = max(0, (size - baseline.size) * 120) * gate
total    = pitchTerm + sizeTerm
score    = total < 4 ? 0 : total - 4
```

주의: 이 상수들은 정밀 튜닝된 값이 아니다. Vision pitch로 라벨별 기록을 모아 검증해야 한다 (`docs/roadmap.md`).

## PostureCore 구성

| 파일 | 내용 |
| --- | --- |
| `Score.swift` | 점수, 진입·회복 기준(3/2 히스테리시스), 심각도 |
| `Engine.swift` | 상태 기계, 시간 상수, EMA 평활(1초 시상수), 적응형 감지 주기 |
| `Calibration.swift` | 기준 잡기 (여러 샘플로 안정성 평가) |
| `Distance.swift` | 앉은 거리 변화 감지 |
| `Feedback.swift` | 화면 단계 (`uncalibrated`, `unavailable`, `good`, `pendingBad`, `bad`, `recovering`). 초기 단계는 `unavailable` |

### 시간 상수

| 항목 | 값 |
| --- | --- |
| 얼굴 사라짐 판정 | 3초 |
| 나쁜 자세 진입 대기 | 3초 |
| 회복 대기 | 2초 |
| 평소 감지 간격 | 1초 (1Hz) |
| 자세 변화 중 간격 | 0.25초 (4Hz) |
| 부재 시 간격 | 3초 (0.33Hz), 부재 60초 이후 적용 |
| 평활 시상수 | 1초 |

코드의 시간 값은 모두 초 단위 `TimeInterval`이다 (`Engine.swift`의 `Timing`).

카메라는 계속 돌리되, 이 간격에 맞춰 일부 프레임만 Vision에 넘긴다. 장시간 부재 시에는 카메라 세션 자체를 멈춘다 (카메라 표시등).

### 기준 잡기 상수 (`Calibration.swift`)

| 항목 | 값 |
| --- | --- |
| 수집 시간 | 5초 |
| 샘플 사이 최대 간격 (시작 시각 포함) | 1.6초 |
| 최소 유효 샘플 | 6개 |
| 허용 누락·무효 샘플 | 2개 |
| pitch 범위 상한 | 6° |
| 얼굴 크기 범위 상한 | 중앙값 대비 0.12 |

기준값은 유효 샘플의 pitch 중앙값과 크기 중앙값이다.

### 거리 변화 상수 (`Distance.swift`)

| 항목 | 값 |
| --- | --- |
| 제안 진입 비율 | 기준 크기 대비 ±0.25 |
| 제안 해제 비율 | 기준 크기 대비 ±0.15 |
| 제안 대기 | 8초 |
| 샘플 사이 최대 간격 | 1.6초 |

## 구현 시 주의

- 얼굴이 사라지면 점수를 마지막 값에 고정하지 않는다. `Timing.lostAfter` 이후 추적을 해제한다.
- 캡처 큐와 `MainActor` 격리를 섞지 않는다 (`docs/architecture.md` 동시성).
- 기준값은 `UserDefaults`에 저장해 재시작 후에도 유지한다.

## 테스트

- 점수, 상태 전이, 기준 잡기, 거리 변화 각각에 Swift Testing 테스트를 둔다. 경계값(진입 3, 회복 2, 3초·2초 대기)을 반드시 포함한다.
- 시간은 주입한다 (`at: TimeInterval` 인자). `Date()`를 로직 안에서 직접 부르지 않는다.

## 상수 변경 기록

상수나 시간 값을 바꾸면 이 표와 테스트를 함께 갱신한다.

| 날짜 | 변경 | 근거 |
| --- | --- | --- |
| 2026-11-26 | 최초 구현 | 점수식 명세 기준 |
| 2026-11-26 | Engine 최초 구현 | 시간 상수 명세 기준 |
| 2026-11-26 | Calibration, Distance 최초 구현 | 명세 기준 |
