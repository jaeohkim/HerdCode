import AppKit
import SwiftUI
import Combine

struct ScreenGeometry {
    let visibleFrame: NSRect
}

enum PanelPlacement {
    static let windowMargin: CGFloat = 12
    static let panelWidth: CGFloat = 340

    static func resolveFrame(
        savedOrigin: NSPoint?,
        height: CGFloat,
        screen: ScreenGeometry
    ) -> NSRect {
        let size = NSSize(width: panelWidth, height: height)
        guard let origin = savedOrigin else {
            return topRightFrame(height: height, screen: screen)
        }
        guard isFullyOnScreen(origin: origin, size: size, screen: screen) else {
            return topRightFrame(height: height, screen: screen)
        }
        return NSRect(origin: origin, size: size)
    }

    static func isFullyOnScreen(origin: NSPoint, size: NSSize, screen: ScreenGeometry) -> Bool {
        let panelRect = NSRect(origin: origin, size: size)
        let safeArea = screen.visibleFrame.insetBy(dx: windowMargin, dy: windowMargin)
        return panelRect.minX >= safeArea.minX
            && panelRect.minY >= safeArea.minY
            && panelRect.maxX <= safeArea.maxX + windowMargin * 2
            && panelRect.maxY <= safeArea.maxY + windowMargin * 2
    }

    static func topRightFrame(height: CGFloat, screen: ScreenGeometry) -> NSRect {
        let visible = screen.visibleFrame
        let x = visible.maxX - panelWidth - windowMargin
        let y = visible.maxY - height - windowMargin
        return NSRect(x: x, y: y, width: panelWidth, height: height)
    }
}

@MainActor
final class FloatingPanelController {
    private enum Constants {
        static let windowOriginKey = "HerdCode.windowOrigin"
        static let panelWidth: CGFloat = PanelPlacement.panelWidth
        static let panelMaxHeightRatio: CGFloat = 0.85
    }

    private let monitor: StatusMonitor
    private(set) var window: NSWindow?
    private var hostingController: NSHostingController<MenuBarView>?
    private var cancellables = Set<AnyCancellable>()
    private var moveObserver: NSObjectProtocol?

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
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            MainActor.assumeIsolated { self.saveOrigin(window) }
        }

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
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let geometry = ScreenGeometry(visibleFrame: screen.visibleFrame)
        return PanelPlacement.resolveFrame(
            savedOrigin: restoredOrigin(),
            height: height,
            screen: geometry
        )
    }

    func saveOrigin(_ window: NSWindow) {
        UserDefaults.standard.set(
            NSStringFromPoint(window.frame.origin),
            forKey: Constants.windowOriginKey
        )
    }

    func restoredOrigin() -> NSPoint? {
        guard let str = UserDefaults.standard.string(forKey: Constants.windowOriginKey),
              !str.isEmpty else { return nil }
        return NSPointFromString(str)
    }

    private func screenForMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }
}
