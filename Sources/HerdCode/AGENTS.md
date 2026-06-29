# Sources/HerdCode — Source Target Knowledge Base

## OVERVIEW

Single SPM `executableTarget`. AppKit shell (NSStatusBar + NSWindow) wrapping SwiftUI content via NSHostingController.

## STRUCTURE

```
Sources/HerdCode/
├── main.swift                    # 13 lines — NSApp init, @MainActor entry
├── AppDelegate.swift             # 80 lines — boot hub, statusItem, globalKeyMonitor
├── FloatingPanelController.swift # 149 lines — NSWindow lifecycle, drag, origin persistence
├── DragHandleView.swift          # 9 lines — NSView subclass, mouseDownCanMoveWindow=true
├── Models/
│   └── DataModels.swift          # 모든 도메인 타입 (AgentStatus, AppState, …)
├── Services/                     # see Services/AGENTS.md
│   └── (5 files)
└── Views/
    └── MenuBarView.swift         # 373 lines — full SwiftUI UI, 리팩터링 후보
```

## WHERE TO LOOK

| Goal | File | Key symbol |
|------|------|------------|
| 앱 진입점 | `main.swift` | `NSApplication.shared.run()` |
| 부트 순서 / DI 연결 | `AppDelegate.swift` | `applicationDidFinishLaunching` |
| ⌥Space 단축키 | `AppDelegate.swift` | `setupGlobalHotKey()`, keyCode=49, `.option` |
| 상태바 아이콘 | `AppDelegate.swift` | `setupStatusItem()` |
| 패널 show/hide | `FloatingPanelController.swift` | `show()` / `hide()` |
| 창 크기 강제 | `FloatingPanelController.swift` | `enforceSize()` |
| 창 위치 저장 | `FloatingPanelController.swift` | `UserDefaults("HerdCode.windowOrigin")` |
| 드래그 이동 | `DragHandleView.swift` | `mouseDownCanMoveWindow = true` |
| 전체 UI 컴포넌트 | `Views/MenuBarView.swift` | `MenuBarView`, private row structs |
| 전체 도메인 타입 | `Models/DataModels.swift` | `AppState`, `AgentStatus`, … |

## LAYOUT RULES — AppKit + SwiftUI Integration

- **NSWindow, not NSPanel.** `.floating` window level 사용. NSPanel은 클릭 통과 문제 발생 — 변경 금지.
- **NSHostingController** 가 SwiftUI를 NSWindow contentView에 브릿지. NSViewController 서브클래스로 교체 금지.
- **DragHandleView** 는 SwiftUI contentView 위에 AppKit subview로 올림. SwiftUI에는 macOS 창 드래그용 `.cursor(.openHand)` 동등물이 없어 AppKit 오버레이 사용.
- **No Storyboard / XIB.** 모든 창 설정은 `FloatingPanelController.init`에서 코드로.
- **enforceSize()** 는 상태 변경으로 layout pass가 생길 때마다 호출해야 함 — SwiftUI가 hosting view를 리사이즈하면 다시 클램프.
- **show() calls monitor.refresh()** — 패널은 항상 신선한 데이터로 열림.

## APPDELEGATE BOOT ORDER

```
applicationDidFinishLaunching
  1. NSApp.setActivationPolicy(.accessory)
  2. StatusMonitor(pollInterval: 5.0)
  3. setupStatusItem()              → ⚡ 메뉴바 아이콘
  4. FloatingPanelController(monitor:)
  5. monitor.$state Combine sink   → UI 자동 갱신
  6. monitor.start()               → 즉시 refresh() + 5초 타이머
  7. setupGlobalHotKey()           → ⌥Space NSEvent.addGlobalMonitor
```

## FILE SIZE NOTES

`Views/MenuBarView.swift` 373줄 — 250줄 상한 초과. `HerdrAgentRow`, `OpencodeSessionRow` private struct들이 리팩터링 대상. 분리 시 이 문서 업데이트 필요.
