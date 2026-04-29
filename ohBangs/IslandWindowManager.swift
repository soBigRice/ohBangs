import AppKit
import Combine
import SwiftUI

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class IslandHitTestHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRectProvider: (() -> NSRect)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let interactiveRectProvider else {
            return super.hitTest(point)
        }

        let interactiveRect = interactiveRectProvider()
        guard interactiveRect.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }
}

@MainActor
final class IslandWindowManager: NSObject, NSWindowDelegate {
    static let shared = IslandWindowManager()

    private var panel: IslandPanel?
    private var settingsPanel: SettingsPanel?
    private var screenObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var testNotificationObserver: NSObjectProtocol?
    private var stateCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private let islandState = IslandStateStore()
    private let settingsStore = AppSettingsStore()
    private let contentProvider: IslandContentProvider = SystemCalendarContentProvider()
    private let systemNotificationBridge = SystemNotificationBridge()

    private let manualXOffset: CGFloat = 0
    private let manualYOffset: CGFloat = 0

    private override init() {}

    func start() {
        if panel == nil {
            panel = makePanel()
            registerScreenObserver()
            observeIslandStateIfNeeded()
            startSystemNotificationBridge()
        }

        guard let panel else { return }

        reposition(panel)
        startContentProviderIfNeeded()
        installInteractionMonitorsIfNeeded()
        updatePanelMousePassthrough()
        panel.orderFrontRegardless()
    }

    func showSettingsPanel() {
        if settingsPanel == nil {
            settingsPanel = makeSettingsPanel()
        }

        guard let settingsPanel else { return }

        islandState.setSettingsPanelPresented(true)
        repositionSettingsPanel(settingsPanel)
        settingsPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> IslandPanel {
        let panelSize = NSSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)

        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = IslandHitTestHostingView(
            rootView: ContentView(
                islandState: islandState,
                settings: settingsStore,
                openSettingsPanel: { [weak self] in
                    self?.showSettingsPanel()
                }
            )
        )
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.interactiveRectProvider = { [weak self] in
            self?.currentInteractiveRect(in: panelSize) ?? .zero
        }
        panel.contentView = hosting

        return panel
    }

    private func makeSettingsPanel() -> SettingsPanel {
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "设置"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: SettingsPanelView(settings: settingsStore))

        return panel
    }

    private func registerScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                self.reposition(panel)
            }
        }
    }

    private func startSystemNotificationBridge() {
        systemNotificationBridge.onNotification = { [weak self] title, subtitle in
            guard let self, self.settingsStore.notificationEnabled else { return }
            self.islandState.presentNotification(title: title, subtitle: subtitle)
        }
        systemNotificationBridge.start()

        testNotificationObserver = NotificationCenter.default.addObserver(
            forName: SystemNotificationBridge.triggerTestNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.systemNotificationBridge.sendTestNotification()
            }
        }
    }

    private func startContentProviderIfNeeded() {
        contentProvider.start { [weak self] content in
            self?.islandState.updateContent(content)
        }
    }

    private func installInteractionMonitorsIfNeeded() {
        if deactivationObserver == nil {
            deactivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.islandState.collapse()
                }
            }
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.islandState.collapse()
                return nil
            }
        }

        let mouseEvents: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseDragged
        ]

        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
                self?.updatePanelMousePassthrough()
                return event
            }
        }

        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
                _ = event
                self?.updatePanelMousePassthrough()
            }
        }
    }

    private func reposition(_ panel: IslandPanel) {
        let size = NSSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let origin = calculateOrigin(targetSize: size, on: panel.screen ?? NSScreen.main)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        updatePanelMousePassthrough()
    }

    private func repositionSettingsPanel(_ panel: NSPanel) {
        let size = panel.frame.size
        let islandOrigin = calculateOrigin(
            targetSize: NSSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight),
            on: panel.screen ?? NSScreen.main
        )
        let origin = NSPoint(
            x: islandOrigin.x + (IslandLayout.panelWidth - size.width) / 2,
            y: islandOrigin.y - size.height - 12
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func observeIslandStateIfNeeded() {
        guard stateCancellable == nil else { return }
        stateCancellable = islandState.$displayState
            .combineLatest(islandState.$isHovering)
            .sink { [weak self] _, _ in
                self?.updatePanelMousePassthrough()
            }

        settingsCancellable = settingsStore.$previewDuration
            .combineLatest(settingsStore.$expandWidth)
            .sink { [weak self] previewDuration, _ in
                self?.islandState.notificationPreviewDuration = .seconds(previewDuration)
                self?.updatePanelMousePassthrough()
            }
    }

    private func updatePanelMousePassthrough() {
        guard let panel else { return }
        let screenPoint = NSEvent.mouseLocation
        let panelPoint = panel.convertPoint(fromScreen: screenPoint)
        let panelSize = panel.frame.size

        // Hover trigger uses a slightly expanded rect for better hit feel,
        // while click handling still uses the strict visual island rect.
        let hoverTriggerRect = currentHoverTriggerRect(in: panelSize)
        let shouldHover = isPointInsideInteractionArea(panelPoint, rect: hoverTriggerRect)
        if shouldHover != islandState.isHovering {
            islandState.setHovering(shouldHover)
        }

        let interactiveRect = currentInteractiveRect(in: panelSize)
        let shouldHandle = isPointInsideInteractionArea(panelPoint, rect: interactiveRect)
        panel.ignoresMouseEvents = !shouldHandle
    }

    private func calculateOrigin(targetSize: NSSize, on screen: NSScreen?) -> NSPoint {
        guard let screen else { return .zero }

        let screenFrame = screen.frame
        let notchCenter = notchCenterX(on: screen) ?? screenFrame.midX
        let topOffset: CGFloat = screen.safeAreaInsets.top > 0 ? 0 : 6

        return NSPoint(
            x: notchCenter - targetSize.width / 2 + manualXOffset,
            y: screenFrame.maxY - targetSize.height - topOffset + manualYOffset
        )
    }

    private func notchCenterX(on screen: NSScreen) -> CGFloat? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }
        return (leftArea.maxX + rightArea.minX) / 2
    }

    private func currentInteractiveRect(in panelSize: NSSize) -> NSRect {
        let islandSize = islandSize(for: islandState.displayState)
        let origin = NSPoint(
            x: (panelSize.width - islandSize.width) / 2,
            y: panelSize.height - islandSize.height
        )
        var rect = NSRect(origin: origin, size: islandSize)

        if islandState.displayState == .expanded {
            rect = rect.insetBy(dx: 0, dy: -10)
            rect.size.width += 44
            rect.origin.x -= 22
        }

        return rect
    }

    private func islandSize(for state: IslandStateStore.DisplayState) -> NSSize {
        switch state {
        case .collapsed:
            return NSSize(width: IslandLayout.collapsedWidth, height: IslandLayout.collapsedHeight)
        case .hint:
            return NSSize(width: settingsStore.expandWidth, height: IslandLayout.hintHeight)
        case .expanded:
            return NSSize(width: IslandLayout.expandedWidth, height: IslandLayout.expandedHeight)
        }
    }

    private func currentHoverTriggerRect(in panelSize: NSSize) -> NSRect {
        let baseRect = currentInteractiveRect(in: panelSize)
        let expansion: NSSize

        switch islandState.displayState {
        case .collapsed:
            expansion = NSSize(width: 18, height: 10)
        case .hint:
            expansion = NSSize(width: 12, height: 8)
        case .expanded:
            expansion = NSSize(width: 6, height: 6)
        }

        let expandedRect = baseRect.insetBy(dx: -expansion.width, dy: -expansion.height)
        let panelBounds = NSRect(origin: .zero, size: panelSize)
        return expandedRect.intersection(panelBounds)
    }

    private func isPointInsideInteractionArea(_ point: NSPoint, rect: NSRect) -> Bool {
        // NSRect.contains excludes top/right edges. Add a tiny tolerance so
        // the island remains clickable when cursor is flush with top edge.
        let edgeTolerance: CGFloat = 1
        return point.x >= rect.minX &&
            point.x <= rect.maxX + edgeTolerance &&
            point.y >= rect.minY &&
            point.y <= rect.maxY + edgeTolerance
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsPanel else { return }
        islandState.setSettingsPanelPresented(false)
    }
}
