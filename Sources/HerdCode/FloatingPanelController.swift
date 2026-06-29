import AppKit
import SwiftUI
import Combine

@MainActor
final class FloatingPanelController {
    private enum Constants {
        static let windowOriginKey = "HerdCode.windowOrigin"
        static let windowMargin: CGFloat = 12
        static let panelWidth: CGFloat = 340
        static let panelMaxHeightRatio: CGFloat = 0.85
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
            contentRect: NSRect(x: 0, y: 0, width: Constants.panelWidth, height: 480),
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
        let preferred = hostingController?.preferredContentSize ?? .zero
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let maxH = screen.visibleFrame.height * Constants.panelMaxHeightRatio
        let newHeight = preferred.height > 0 ? min(preferred.height, maxH) : window.frame.height
        let newSize = NSSize(width: Constants.panelWidth, height: newHeight)
        if abs(window.frame.width - newSize.width) > 1 || abs(window.frame.height - newSize.height) > 1 {
            let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - newSize.height)
            window.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: false)
        }
    }

    private func currentPanelHeight() -> CGFloat {
        let preferred = hostingController?.preferredContentSize.height ?? 0
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let maxH = screen.visibleFrame.height * Constants.panelMaxHeightRatio
        return preferred > 0 ? min(preferred, maxH) : 480
    }

    private func targetWindowFrame() -> NSRect {
        let height = currentPanelHeight()
        let size = NSSize(width: Constants.panelWidth, height: height)
        if let origin = restoredOrigin(), isOnScreen(origin: origin, size: size) {
            return NSRect(origin: origin, size: size)
        }
        return topRightFrame(height: height)
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

    private func topRightFrame(height: CGFloat) -> NSRect {
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = visible.maxX - Constants.panelWidth - Constants.windowMargin
        let y = visible.maxY - height - Constants.windowMargin
        return NSRect(x: x, y: y, width: Constants.panelWidth, height: height)
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
