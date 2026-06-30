# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-29  
**Commit:** dc488cd  
**Branch:** main

## OVERVIEW

macOS 메뉴바 앱 — `herdr`(멀티-에이전트 터미널 오케스트레이터)와 `opencode`(AI 코딩 도구)의 상태를 5초 폴링으로 모니터링하고 ⌥Space 글로벌 단축키로 플로팅 패널을 열어 에이전트 pane으로 직접 jump하는 도구.  
Stack: Swift 5.9 + AppKit + Combine + SQLite3 (시스템 링크). 외부 Swift 패키지 의존성 없음.

## STRUCTURE

```
HerdCode/
├── Package.swift              # SPM 매니페스트, 외부 의존성 없음
├── Sources/HerdCode/          # 단일 executableTarget
│   ├── main.swift             # NSApplication 진입점 (@MainActor)
│   ├── AppDelegate.swift      # 앱 부트스트래핑 + 글로벌 단축키(⌥Space)
│   ├── FloatingPanelController.swift  # NSWindow(floating) + 위치 저장/복원
│   ├── DragHandleView.swift   # 패널 드래그 핸들 (NSView)
│   ├── Models/DataModels.swift        # 전체 도메인 타입 (AppState 등)
│   ├── Services/              # 비즈니스 로직 (5개 파일)
│   └── Views/MenuBarView.swift        # 전체 UI (SwiftUI on AppKit)
└── Tests/HerdCodeTests/       # XCTest 단위 테스트
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| 앱 시작/종료 로직 | `AppDelegate.swift` | applicationDidFinishLaunching |
| 상태 폴링/갱신 | `Services/StatusMonitor.swift` | @Published state, 5초 간격 |
| herdr CLI 연동 | `Services/HerdrService.swift` | `/opt/homebrew/bin/herdr` 호출 |
| opencode 데이터 | `Services/OpencodeService.swift` | SQLite 직접 조회 |
| pane jump 로직 | `Services/TerminalJumpResolver.swift` | 순수 함수 |
| 도메인 모델 전체 | `Models/DataModels.swift` | AgentStatus, AppState 등 |
| UI 뷰 컴포넌트 | `Views/MenuBarView.swift` | Row 서브뷰도 같은 파일 |
| 패널 위치/크기 | `FloatingPanelController.swift` | UserDefaults에 origin 저장 |
| 테스트 헬퍼 | `Tests/HerdCodeTests/TestHelpers.swift` | Fake* 구현체, LockedEvents |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `AppDelegate` | class (@MainActor) | AppDelegate.swift | 앱 부트스트래핑 허브 |
| `StatusMonitor` | ObservableObject actor | Services/StatusMonitor.swift | 상태 관리 중심부 |
| `AppState` | struct | Models/DataModels.swift | 전체 UI 상태 값타입 |
| `HerdrService` | actor | Services/HerdrService.swift | herdr CLI 게이트웨이 |
| `OpencodeService` | actor | Services/OpencodeService.swift | SQLite 데이터 소스 |
| `TerminalJumpResolver` | enum(namespace) | Services/TerminalJumpResolver.swift | pane 결정 순수함수 |
| `FloatingPanelController` | class (@MainActor) | FloatingPanelController.swift | NSWindow 라이프사이클 |
| `MenuBarView` | SwiftUI View | Views/MenuBarView.swift | 최상위 UI 컴포넌트 |
| `JumpLogging` | protocol | Services/JumpLogger.swift | 테스트 DI 포인트 |
| `JumpExecuting` | protocol | Services/HerdrService.swift | 테스트 DI 포인트 |
| `AppActivating` | protocol | Services/HerdrService.swift | 테스트 DI 포인트 |
| `HerdrError` | enum (LocalizedError) | Services/HerdrService.swift | jump 오류 체계 |

### 부트스트래핑 순서
```
main.swift → AppDelegate.applicationDidFinishLaunching
  1. NSApp.setActivationPolicy(.accessory)   ← Dock 아이콘 숨김
  2. StatusMonitor(pollInterval: 5.0)
  3. setupStatusItem() → 메뉴바 ⚡ 아이콘
  4. FloatingPanelController(monitor:)
  5. monitor.$state Combine sink
  6. monitor.start() → 즉시 refresh() + 타이머
  7. setupGlobalHotKey() → ⌥Space NSEvent.addGlobalMonitor
```

## CONVENTIONS

- **Actor isolation**: `HerdrService`, `OpencodeService`는 `actor`. `AppDelegate`, `FloatingPanelController`는 `@MainActor final class`.
- **Combine 패턴**: `monitor.$state.receive(on: RunLoop.main).sink { }.store(in: &cancellables)` — cancellables는 항상 `Set<AnyCancellable>`.
- **프로토콜 DI**: 외부 시스템 연동은 반드시 프로토콜 추상화(`JumpLogging`, `JumpExecuting`, `AppActivating`) — 테스트에서 Fake* 구현체로 교체.
- **오류 로그 접두사**: jump 실패 로그는 반드시 `[HerdCodeJumpError]` 접두사 (`JumpLogger` 경유).
- **UserDefaults 키**: `HerdCode.` 접두사 필수 (예: `HerdCode.windowOrigin`, `HerdCode.fontScale`).
- **CodingKeys**: JSON 스네이크케이스 ↔ Swift 카멜케이스 변환은 명시적 `CodingKeys` enum 사용 (자동 디코더 전략 사용 안 함).

## ANTI-PATTERNS (THIS PROJECT)

- **@MainActor actor 혼용 금지**: actor 타입에 `@MainActor`를 붙이지 않음.
- **직접 herdr 경로 하드코딩 금지**: `/opt/homebrew/bin/herdr`는 `HerdrService.init(herdrPath:)` 기본값에만 존재.
- **SQLite 쓰기 금지**: `OpencodeService`는 **읽기 전용** (`SQLITE_OPEN_READONLY`). opencode DB에 절대 쓰기 금지.
- **Dock 아이콘 노출 금지**: `NSApp.setActivationPolicy(.accessory)` 항상 유지.
- **SwiftUI NavigationView/Stack 금지**: 패널 UI는 `VStack` + `NSWindow` 직접 관리.

## UNIQUE STYLES

- **한국어 UI 문자열**: 모든 사용자 노출 문자열(레이블, 에러 메시지, 알림)은 한국어.
- **Row 뷰 private**: `HerdrAgentRow`, `OpencodeSessionRow` 등은 `private struct` — `MenuBarView.swift` 내부에만 존재.
- **`fontScale` AppStorage**: 모든 row 폰트 크기는 `fontScale` 곱셈으로 스케일 (`scaled(_:)` 헬퍼).

## COMMANDS

```bash
# 개발 빌드
swift build

# 실행
swift run HerdCode

# Release 빌드
swift build -c release

# 전체 테스트
swift test

# 병렬 테스트
swift test --parallel

# 특정 테스트
swift test --filter TerminalJumpResolverTests

# 빌드 캐시 삭제
swift package clean
```

## REFERENCES

- **herdr 공식 문서**: https://herdr.dev/ — CLI 레퍼런스, 세션/소켓 구조, remote attach 동작 등 herdr 관련 모든 내용은 이 문서를 우선 참조.
  - CLI 레퍼런스: https://herdr.dev/docs/cli-reference/
  - Remote/SSH 동작: https://herdr.dev/docs/persistence-remote/
  - Socket API: https://herdr.dev/docs/socket-api/

## NOTES

- herdr 바이너리가 `/opt/homebrew/bin/herdr`에 없으면 `HerdrError.herdrNotFound` 발생.
- opencode DB 경로: `~/.local/share/opencode/opencode.db` — opencode 미실행 시 `OpencodeError.cannotOpenDB` 발생.
- Ghostty 미설치 시 jump 불가 — `GhosttyNSWorkspaceActivator.canActivate()` false.
- `.build/` 디렉토리는 `.gitignore`됨 (arm64-apple-macosx 전용).
- CI/CD 파이프라인 없음 — PR 시 로컬에서 `swift test` 수동 실행 필요.
- `Views/MenuBarView.swift` 373줄 — 단일 파일 크기 임계치 초과 (리팩터링 후보).
