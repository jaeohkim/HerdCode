import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panelController: FloatingPanelController?
    private var monitor: StatusMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

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
        if let m = localKeyMonitor  { NSEvent.removeMonitor(m) }
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
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            else { return }
            DispatchQueue.main.async {
                self?.panelController?.toggle()
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            else { return event }
            DispatchQueue.main.async {
                self.panelController?.toggle()
            }
            return nil
        }
    }
}
