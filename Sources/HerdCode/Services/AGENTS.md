# Services/ — Agent Context

**Scope:** `Sources/HerdCode/Services/` only. 앱 전체 컨벤션은 root `AGENTS.md` 참조.

## OVERVIEW

5개 파일로 구성된 비즈니스 로직 레이어. `StatusMonitor`가 중심이고, 나머지 4개는 각자 단일 책임을 가진다.

## WHERE TO LOOK

| 파일 | 책임 | 핵심 메서드 |
|------|------|------------|
| `StatusMonitor.swift` | 상태 폴링 허브 (5초 타이머) | `start()`, `stop()`, `refresh()`, `jumpToAgent()`, `jumpToSession()`, `rowState(for:)` |
| `HerdrService.swift` | herdr CLI 게이트웨이 | `fetchSessions()`, `fetchAgents()`, `fetchWorkspaces()`, `focusPane()` |
| `OpencodeService.swift` | opencode SQLite 읽기 전용 | `fetchRecentSessions(limit:)`, `fetchTodos(for:)`, `close()` |
| `TerminalJumpResolver.swift` | pane 결정 순수 함수 | `rowState(for:HerdrAgent)`, `rowState(for:OpencodeSession,agents:)` |
| `JumpLogger.swift` | jump 실패 로깅 DI | `JumpLogging` 프로토콜, `JumpLogger` struct |

## KEY PROTOCOLS

| 프로토콜 | 정의 위치 | 목적 |
|----------|-----------|------|
| `JumpExecuting` | `HerdrService.swift` | herdr pane focus 추상화 (테스트용 Fake 교체) |
| `AppActivating` | `HerdrService.swift` | Ghostty 앱 활성화 추상화 |
| `JumpLogging` | `JumpLogger.swift` | 로그 싱크 주입 (테스트용 LockedEvents 연동) |

## AGENTROWSTATE

`TerminalJumpResolver.AgentRowState` — UI row 하나의 완전한 상태:

```swift
// uiKey: 메뉴바 표시 키, focusTarget: nil이면 jump 비활성
struct AgentRowState {
    let uiKey: String
    let isEnabled: Bool
    let focusTarget: String?
    let helpText: String   // 한국어 도움말
}
```

세션→에이전트 매칭 우선순위: `focused` > `working` > `paneId` 사전순.

## ERROR HANDLING

| 타입 | 케이스 | 처리 위치 |
|------|--------|-----------|
| `HerdrError` | `invalidOutput`, `herdrNotFound`, `activationFailed`, `jumpFailed` | `StatusMonitor.jumpToAgent()` 에서 catch |
| `OpencodeError` | `cannotOpenDB`, 기타 SQLite 에러 | `StatusMonitor.refresh()` 에서 catch |

jump 실패 로그는 반드시 `JumpLogger`를 경유하고 `[HerdCodeJumpError]` 접두사 필수:

```swift
// 직접 print/NSLog 금지
logger.log("[HerdCodeJumpError] focusPane 실패: \(error)")
```

## ANTI-PATTERNS (Services 한정)

- **`StatusMonitor`에 UI 로직 추가 금지** — row 표시 결정은 `TerminalJumpResolver`가 담당.
- **`OpencodeService`에 쓰기 쿼리 금지** — `SQLITE_OPEN_READONLY`로 열림, INSERT/UPDATE 시 런타임 에러.
- **`HerdrService` 경로 재선언 금지** — `/opt/homebrew/bin/herdr`는 `HerdrService.init(herdrPath:)` 기본값에만 존재.
- **`TerminalJumpResolver`에 상태 저장 금지** — `enum` 네임스페이스, 케이스 없음, 순수 함수만.
- **`StatusMonitor` 외부에서 직접 poll 트리거 금지** — `refresh()`는 내부 타이머와 `start()` 호출에서만.
