import AppKit
import SwiftUI
import Combine

@MainActor
final class FloatingPanelController {
    private enum Constants {
        static let windowOriginKey = "HerdCode.windowOrigin"
        static let windowMargin: CGFloat = 12
        static let panelWidth: CGFloat = 340
        static let panelHeight: CGFloat = 480
    }

    private let monitor: StatusMonitor
    private(set) var window: NSWindow?
    private var hostingController: NSHostingController<MenuBarView>?
    private var cancellables = Set<AnyCancellable>()

    init(monitor: StatusMonitor) {
        self.monitor = monitor
        self.window = makeWindow()

        monitor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.hostingController?.rootView = MenuBarView(monitor: self.monitor)
                self.enforceSize(window)
            }
            .store(in: &cancellables)
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible { hide() } else { show() }
    }

    func show() {
        guard let window else { return }

        Task { await monitor.refresh() }

        let targetFrame = targetWindowFrame()
        window.setFrame(targetFrame, display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        if let window { saveOrigin(window) }
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let hc = NSHostingController(rootView: MenuBarView(monitor: monitor))
        hc.sizingOptions = .preferredContentSize
        self.hostingController = hc

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Constants.panelWidth, height: Constants.panelHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hc
        window.isReleasedWhenClosed = false
        window.title = "HerdCode"
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        installDragHandle(in: window)

        return window
    }

    private func enforceSize(_ window: NSWindow) {
        let current = window.frame
        if abs(current.width - Constants.panelWidth) > 1 || abs(current.height - Constants.panelHeight) > 1 {
            window.setContentSize(NSSize(width: Constants.panelWidth, height: Constants.panelHeight))
        }
    }

    private func targetWindowFrame() -> NSRect {
        let size = NSSize(width: Constants.panelWidth, height: Constants.panelHeight)
        if let origin = restoredOrigin(), isOnScreen(origin: origin, size: size) {
            return NSRect(origin: origin, size: size)
        }
        return topRightFrame()
    }

    private func saveOrigin(_ window: NSWindow) {
        UserDefaults.standard.set(
            NSStringFromPoint(window.frame.origin),
            forKey: Constants.windowOriginKey
        )
    }

    private func restoredOrigin() -> NSPoint? {
        guard let str = UserDefaults.standard.string(forKey: Constants.windowOriginKey),
              !str.isEmpty else { return nil }
        return NSPointFromString(str)
    }

    private func isOnScreen(origin: NSPoint, size: NSSize) -> Bool {
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return NSScreen.screens.contains { $0.frame.contains(center) }
    }

    private func topRightFrame() -> NSRect {
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = visible.maxX - Constants.panelWidth - Constants.windowMargin
        let y = visible.maxY - Constants.panelHeight - Constants.windowMargin
        return NSRect(x: x, y: y, width: Constants.panelWidth, height: Constants.panelHeight)
    }

    private func screenForMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    private func installDragHandle(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let handle = DragHandleView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - 40,
            width: max(0, contentView.bounds.width - 50),
            height: 40
        ))
        handle.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(handle, positioned: .above, relativeTo: nil)
    }
}
