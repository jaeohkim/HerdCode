# TEST DIRECTORY KNOWLEDGE BASE

**Scope:** `Tests/HerdCodeTests/` only. 컨벤션, 프로젝트 구조, 도메인 모델은 root `AGENTS.md` 참조.

## OVERVIEW

XCTest suite for HerdCode — 순수 함수 resolver 테스트, jump 실행 플로우 테스트, 패널 가시성 테스트. 모든 동시성은 `@unchecked Sendable` + `NSLock`으로 처리.

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Fake DI 객체 | `TestHelpers.swift` | 모든 Fake* 타입 여기에 |
| Resolver 로직 테스트 | `TerminalJumpResolverTests.swift` | 순수 함수, async 없음 |
| Jump 실행 플로우 | `HerdCodeJumpExecutionTests.swift` | Fake* 3종 모두 사용 |
| 패널 show/hide | `HerdCodePanelVisibilityTests.swift` | 가시성 assertion 위주 |
| StatusMonitor jump | `HerdCodeStatusMonitorJumpTests.swift` | monitor 레벨 jump 흐름 |
| Ghostty 연기 테스트 | `HerdCodeGhosttyLiveSmokeTests.swift` | 실기기 smoke 테스트 |

## FAKE OBJECTS

| Type | Protocol | Captures |
|------|----------|----------|
| `FakeJumpExecutor` | `JumpExecuting` | `focusPane` 호출을 closure handler로 캡처 |
| `FakeAppActivator` | `AppActivating` | `activate` 호출을 closure handler로 캡처 |
| `TestJumpLogger` | `JumpLogging` | 로그 라인을 `[String]`에 NSLock으로 수집 |
| `FakeFailure` | `LocalizedError` | `message: String` 단일 프로퍼티 |

Thread-safe 컨테이너 (프로토콜 아님):

| Type | Stores | Use When |
|------|--------|----------|
| `LockedEvents` | `[String]` append + snapshot | Task 경계 넘는 순서 있는 이벤트 캡처 |
| `LockedFlag` | `Bool` | 단일 yes/no 시그널 |

## PATTERNS

**Fake 주입** — full DI init 사용:
```swift
HerdrService(
    herdrPath: "/fake",
    appActivator: FakeAppActivator { ... },
    jumpExecutor: FakeJumpExecutor { ... },
    jumpLogger: TestJumpLogger()
)
```

**비동기 이벤트 캡처** — `LockedEvents` snapshot:
```swift
let events = LockedEvents()
// ... 액션 트리거 ...
XCTAssertEqual(events.snapshot(), ["expected"])
```

## KEY RULES

- `@testable import HerdCode` 는 테스트 파일에만. `TestHelpers.swift`에 금지.
- 모든 `Fake*` 타입은 `@unchecked Sendable` — Swift Concurrency Task 캡처에 필수.
- `NSLock` 만 사용. actor나 `DispatchQueue` 사용 금지.
- 오류 로그 assertion은 반드시 `[HerdCodeJumpError]` 접두사 확인 (`JumpLogger` 경유).
- `TerminalJumpResolverTests` 우선순위 커버: focused > working > paneId 사전순.
