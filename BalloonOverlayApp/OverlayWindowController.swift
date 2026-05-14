import AppKit
import SwiftUI

final class OverlayWindowController {
    private let settings: OverlaySettings
    private var windows: [NSWindow] = []
    private var presentationID = UUID()

    init(settings: OverlaySettings) {
        self.settings = settings
    }

    func show() {
        closeExistingWindows()

        let screens = NSScreen.screens
        let currentPresentationID = UUID()
        presentationID = currentPresentationID

        windows = screens.map { screen in
            let content = BalloonOverlayView(settings: settings) { [weak self] in
                guard self?.presentationID == currentPresentationID else { return }
                self?.closeExistingWindows()
            }

            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content)
            window.orderFrontRegardless()
            return window
        }
    }

    private func closeExistingWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}
