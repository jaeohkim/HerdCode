import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panelController: FloatingPanelController?
    private var monitor: StatusMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 독(Dock)에 아이콘 표시하지 않음
        NSApp.setActivationPolicy(.accessory)

        let monitor = StatusMonitor(pollInterval: 5.0)
        self.monitor = monitor

        setupStatusItem()
        setupPanelController(monitor: monitor)

        // 상태 변경마다 메뉴바 타이틀 갱신 (Combine sink)
        monitor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.updateStatusItemTitle(newState.menuBarTitle)
            }
            .store(in: &cancellables)

        monitor.start()
        setupGlobalHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        cancellables.removeAll()
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title  = "⚡"
            button.font   = NSFont.systemFont(ofSize: 13)
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    private func updateStatusItemTitle(_ title: String) {
        statusItem?.button?.title = title
    }

    private func setupPanelController(monitor: StatusMonitor) {
        panelController = FloatingPanelController(monitor: monitor)
    }

    @objc private func togglePanel() {
        guard statusItem?.button != nil else { return }
        panelController?.toggle()
    }

    // MARK: - Global Hotkey (⌥Space)

    private func setupGlobalHotKey() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌥Space: keyCode 49 = Space, modifierFlags must be exactly .option
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            else { return }
            DispatchQueue.main.async {
                self?.panelController?.toggle()
            }
        }
    }
}
