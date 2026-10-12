import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits above the menu bar.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // No .fullScreenAuxiliary, so it stays off full-screen Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit over the menu bar instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets clicks land on the first try even though the panel is never key beforehand.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the notch panel: places it over the notch, shows/hides it for display changes and
/// full-screen apps, and expands/collapses it on hover.
///
/// The window is always the expanded size, so it's toggled between ignoring mouse events
/// (clicks fall through to the menu bar) and accepting them, based on where the cursor is.
@MainActor
final class NotchWindowController {
    private let model: NotchModel
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var notchCenterX: CGFloat = 0

    private var globalMonitor: Any?
    private var pollTimer: Timer?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var isShown = false

    private static let expandDelay: TimeInterval = 0.1
    private static let collapseDelay: TimeInterval = 0.25

    init(model: NotchModel) {
        self.model = model

        let hosting = FirstMouseHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateVisibility()
                    // The window list can lag behind the Space switch animation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.updateVisibility() }
                }
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateMouse() }
        }

        layout()
    }

    // MARK: - Placement

    private func layout() {
        // Built-in notched display only; no fake notch on external monitors.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            self.screen = nil
            updateVisibility()
            return
        }
        self.screen = screen

        let notchWidth = screen.frame.width - left.width - right.width
        model.notchSize = CGSize(width: notchWidth, height: screen.safeAreaInsets.top)
        notchCenterX = screen.frame.minX + left.width + notchWidth / 2

        let size = model.windowSize
        panel.setFrame(NSRect(x: notchCenterX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        updateVisibility()
    }

    private func updateVisibility() {
        let shouldShow = screen != nil && !isFullScreenAppFrontmost()
        guard shouldShow != isShown else { return }
        isShown = shouldShow
        if shouldShow {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
            setInteractive(false)
            model.setExpanded(false)
        }
    }

    /// True if the frontmost app has a window covering the whole notched screen.
    private func isFullScreenAppFrontmost() -> Bool {
        guard let screen, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // CG window bounds use a top-left origin relative to the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenRect = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height)

        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.contains(screenRect)
        }
    }

    // MARK: - Hover

    private var collapsedRect: NSRect {
        let size = model.collapsedSize
        let centerX = notchCenterX + model.collapsedOffsetX
        let top = screen?.frame.maxY ?? 0
        // Extend above the screen edge so a cursor pinned to the top still counts.
        return NSRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height + 4)
    }

    private var expandedRect: NSRect {
        let size = model.expandedSize
        let top = screen?.frame.maxY ?? 0
        return NSRect(x: notchCenterX - size.width / 2, y: top - size.height, width: size.width, height: size.height + 4)
            .insetBy(dx: -8, dy: -8)
    }

    private func evaluateMouse() {
        guard isShown else { return }
        let mouse = NSEvent.mouseLocation
        let inside = (model.isExpanded ? expandedRect : collapsedRect).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons != 0
        // Keep a drag that started in the panel (e.g. the scrubber) alive past its edge.
        if !(dragging && model.isExpanded && !panel.ignoresMouseEvents) {
            setInteractive(inside)
        }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !model.isExpanded && expandWork == nil {
                schedule(&expandWork, after: Self.expandDelay) { [weak self] in
                    guard let self else { return }
                    self.expandWork = nil
                    if self.collapsedRect.contains(NSEvent.mouseLocation) {
                        self.model.setExpanded(true)
                    } else {
                        self.setInteractive(false)
                    }
                }
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
            // Don't collapse mid-drag (e.g. scrubbing past the edge).
            if model.isExpanded && collapseWork == nil && !dragging {
                schedule(&collapseWork, after: Self.collapseDelay) { [weak self] in
                    guard let self else { return }
                    self.collapseWork = nil
                    guard !self.expandedRect.contains(NSEvent.mouseLocation) else { return }
                    self.model.setExpanded(false)
                    self.setInteractive(false)
                }
            }
        }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// While the panel takes mouse events the global monitor goes quiet (events go to us),
    /// so poll the cursor position until it's click-through again.
    private func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
        if interactive, pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateMouse() }
            }
        } else if !interactive {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
