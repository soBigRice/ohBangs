import AppKit
import SwiftUI

@MainActor
final class IslandWindowManager {
    static let shared = IslandWindowManager()

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private let islandState = IslandStateStore()
    private let contentProvider: IslandContentProvider = MockIslandContentProvider()

    private let manualXOffset: CGFloat = 0
    private let manualYOffset: CGFloat = 0

    private init() {}

    func start() {
        if panel == nil {
            panel = makePanel()
            registerScreenObserver()
        }

        guard let panel else { return }

        reposition(panel)
        startContentProviderIfNeeded()
        installInteractionMonitorsIfNeeded()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panelSize = NSSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)

        let panel = NSPanel(
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
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: ContentView(islandState: islandState))
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
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
    }

    private func reposition(_ panel: NSPanel) {
        let size = NSSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let origin = calculateOrigin(targetSize: size, on: panel.screen ?? NSScreen.main)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
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
}
