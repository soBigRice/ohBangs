import AppKit
import Combine
import SwiftUI

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
final class IslandWindowManager {
    static let shared = IslandWindowManager()

    private var panel: IslandPanel?
    private var screenObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var stateCancellable: AnyCancellable?
    private let islandState = IslandStateStore()
    private let contentProvider: IslandContentProvider = MockIslandContentProvider()

    private let manualXOffset: CGFloat = 0
    private let manualYOffset: CGFloat = 0

    private init() {}

    func start() {
        if panel == nil {
            panel = makePanel()
            registerScreenObserver()
            observeIslandStateIfNeeded()
        }

        guard let panel else { return }

        reposition(panel)
        startContentProviderIfNeeded()
        installInteractionMonitorsIfNeeded()
        updatePanelMousePassthrough()
        panel.orderFrontRegardless()
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

        let hosting = IslandHitTestHostingView(rootView: ContentView(islandState: islandState))
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.interactiveRectProvider = { [weak self] in
            self?.currentInteractiveRect(in: panelSize) ?? .zero
        }
        panel.contentView = hosting

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

    private func observeIslandStateIfNeeded() {
        guard stateCancellable == nil else { return }
        stateCancellable = islandState.$displayState
            .combineLatest(islandState.$isHovering)
            .sink { [weak self] _, _ in
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
        return NSRect(origin: origin, size: islandSize)
    }

    private func islandSize(for state: IslandStateStore.DisplayState) -> NSSize {
        switch state {
        case .collapsed:
            return NSSize(width: IslandLayout.collapsedWidth, height: IslandLayout.collapsedHeight)
        case .hint:
            return NSSize(width: IslandLayout.hintWidth, height: IslandLayout.hintHeight)
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
}
