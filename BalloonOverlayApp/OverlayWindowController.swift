import AppKit
import SwiftUI

struct OverlayClick {
    let screenFrame: CGRect
    let point: CGPoint
}

struct OverlayScroll {
    let screenFrame: CGRect
    let deltaX: CGFloat
    let deltaY: CGFloat
}

enum OverlayDragPhase {
    case began
    case changed
    case ended
    case cancelled
}

struct OverlayDrag {
    let screenFrame: CGRect
    let point: CGPoint
    let phase: OverlayDragPhase
}

struct OverlayInteractionFrames {
    var balloon: CGRect = .zero
    var image: CGRect = .zero
    var backBadge: CGRect = .zero
    var triangle: CGRect = .zero
    var explanationButton: CGRect = .zero
    var explanationBubble: CGRect = .zero
    var explanationScrollArea: CGRect = .zero
    var explanationCloseButton: CGRect = .zero
    var imagePreview: CGRect = .zero
    var isShowingExplanation = false
    var isShowingImagePreview = false

    func contains(_ point: CGPoint) -> Bool {
        if isShowingImagePreview {
            return imagePreview.contains(point)
        }
        if isShowingExplanation {
            return explanationBubble.contains(point)
                || explanationCloseButton.contains(point)
        }
        return balloon.contains(point)
            || image.contains(point)
            || backBadge.contains(point)
            || triangle.contains(point)
            || explanationButton.contains(point)
    }

    func shouldPassThroughToSubview(_ point: CGPoint) -> Bool {
        if isShowingExplanation {
            let scrollerHitFrame = CGRect(
                x: explanationScrollArea.maxX - 22,
                y: explanationScrollArea.minY,
                width: 22,
                height: explanationScrollArea.height
            )
            return scrollerHitFrame.contains(point)
        }
        return false
    }

    func shouldForwardScrollWheel(_ point: CGPoint) -> Bool {
        if isShowingImagePreview {
            return imagePreview.contains(point)
        }
        if isShowingExplanation {
            return explanationScrollArea.contains(point)
        }
        return false
    }

    func shouldSendScrollToOverlay(_ point: CGPoint) -> Bool {
        isShowingImagePreview && imagePreview.contains(point)
    }

    func shouldSendDragToOverlay(_ point: CGPoint) -> Bool {
        isShowingImagePreview && imagePreview.contains(point)
    }
}

final class OverlayInteractionRegistry {
    static let shared = OverlayInteractionRegistry()

    private var framesByScreen: [String: OverlayInteractionFrames] = [:]

    func update(screenFrame: CGRect, frames: OverlayInteractionFrames) {
        framesByScreen[key(for: screenFrame)] = frames
        NotificationCenter.default.post(name: .overlayInteractionFramesChanged, object: nil)
    }

    func remove(screenFrame: CGRect) {
        framesByScreen.removeValue(forKey: key(for: screenFrame))
    }

    func contains(screenFrame: CGRect, point: CGPoint) -> Bool {
        framesByScreen[key(for: screenFrame)]?.contains(point) ?? false
    }

    func shouldPassThroughToSubview(screenFrame: CGRect, point: CGPoint) -> Bool {
        framesByScreen[key(for: screenFrame)]?.shouldPassThroughToSubview(point) ?? false
    }

    func shouldForwardScrollWheel(screenFrame: CGRect, point: CGPoint) -> Bool {
        framesByScreen[key(for: screenFrame)]?.shouldForwardScrollWheel(point) ?? false
    }

    func shouldSendScrollToOverlay(screenFrame: CGRect, point: CGPoint) -> Bool {
        framesByScreen[key(for: screenFrame)]?.shouldSendScrollToOverlay(point) ?? false
    }

    func shouldSendDragToOverlay(screenFrame: CGRect, point: CGPoint) -> Bool {
        framesByScreen[key(for: screenFrame)]?.shouldSendDragToOverlay(point) ?? false
    }

    func sameScreen(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        key(for: lhs) == key(for: rhs)
    }

    private func key(for frame: CGRect) -> String {
        "\(Int(frame.minX)):\(Int(frame.minY)):\(Int(frame.width)):\(Int(frame.height))"
    }
}

extension Notification.Name {
    static let overlayClick = Notification.Name("BalloonOverlayApp.overlayClick")
    static let overlayScroll = Notification.Name("BalloonOverlayApp.overlayScroll")
    static let overlayDrag = Notification.Name("BalloonOverlayApp.overlayDrag")
    static let overlayInteractionFramesChanged = Notification.Name("BalloonOverlayApp.overlayInteractionFramesChanged")
}

final class PassthroughOverlayHostingView<Content: View>: NSHostingView<Content> {
    private var screenFrame: CGRect

    init(rootView: Content, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required init(rootView: Content) {
        self.screenFrame = .zero
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let overlayPoint = overlayCoordinatePoint(from: point)
        guard OverlayInteractionRegistry.shared.contains(screenFrame: screenFrame, point: overlayPoint) else {
            return nil
        }

        if OverlayInteractionRegistry.shared.shouldPassThroughToSubview(screenFrame: screenFrame, point: overlayPoint) {
            return super.hitTest(point) ?? self
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = overlayCoordinatePoint(from: convert(event.locationInWindow, from: nil))
        guard OverlayInteractionRegistry.shared.contains(screenFrame: screenFrame, point: point) else {
            return
        }

        if OverlayInteractionRegistry.shared.shouldSendDragToOverlay(screenFrame: screenFrame, point: point) {
            NotificationCenter.default.post(
                name: .overlayDrag,
                object: OverlayDrag(screenFrame: screenFrame, point: point, phase: .began)
            )
        }

        NotificationCenter.default.post(
            name: .overlayClick,
            object: OverlayClick(screenFrame: screenFrame, point: point)
        )
    }

    override func mouseDragged(with event: NSEvent) {
        let point = overlayCoordinatePoint(from: convert(event.locationInWindow, from: nil))
        guard OverlayInteractionRegistry.shared.shouldSendDragToOverlay(screenFrame: screenFrame, point: point) else {
            super.mouseDragged(with: event)
            return
        }

        NotificationCenter.default.post(
            name: .overlayDrag,
            object: OverlayDrag(screenFrame: screenFrame, point: point, phase: .changed)
        )
    }

    override func mouseUp(with event: NSEvent) {
        let point = overlayCoordinatePoint(from: convert(event.locationInWindow, from: nil))
        if OverlayInteractionRegistry.shared.shouldSendDragToOverlay(screenFrame: screenFrame, point: point) {
            NotificationCenter.default.post(
                name: .overlayDrag,
                object: OverlayDrag(screenFrame: screenFrame, point: point, phase: .ended)
            )
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let rawPoint = convert(event.locationInWindow, from: nil)
        let point = overlayCoordinatePoint(from: rawPoint)

        if OverlayInteractionRegistry.shared.shouldSendScrollToOverlay(screenFrame: screenFrame, point: point) {
            NotificationCenter.default.post(
                name: .overlayScroll,
                object: OverlayScroll(
                    screenFrame: screenFrame,
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY
                )
            )
            return
        }

        guard OverlayInteractionRegistry.shared.shouldForwardScrollWheel(screenFrame: screenFrame, point: point),
              let scrollView = scrollView(at: rawPoint, in: self) else {
            super.scrollWheel(with: event)
            return
        }

        scrollView.scrollWheel(with: event)
    }

    private func overlayCoordinatePoint(from point: NSPoint) -> CGPoint {
        if isFlipped {
            return CGPoint(x: point.x, y: point.y)
        }
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func scrollView(at point: NSPoint, in view: NSView) -> NSScrollView? {
        for subview in view.subviews.reversed() {
            let pointInSubview = subview.convert(point, from: view)
            guard subview.bounds.contains(pointInSubview) else { continue }
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let scrollView = scrollView(at: pointInSubview, in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

final class OverlayWindowController {
    private let settings: OverlaySettings
    private var windows: [NSWindow] = []
    private var presentationID = UUID()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var framesObserver: NSObjectProtocol?

    var isShowing: Bool {
        !windows.isEmpty
    }

    init(settings: OverlaySettings) {
        self.settings = settings
    }

    func show(onFinished: (() -> Void)? = nil) {
        closeExistingWindows()

        let screens = NSScreen.screens
        let currentPresentationID = UUID()
        presentationID = currentPresentationID

        windows = screens.map { screen in
            let content = BalloonOverlayView(settings: settings, screenFrame: screen.frame) { [weak self] in
                guard self?.presentationID == currentPresentationID else { return }
                self?.closeExistingWindows()
                onFinished?()
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
            window.contentView = PassthroughOverlayHostingView(rootView: content, screenFrame: screen.frame)
            window.orderFrontRegardless()
            return window
        }
        installPassthroughUpdater()
        updateMousePassthrough()
    }

    private func closeExistingWindows() {
        windows.forEach { window in
            OverlayInteractionRegistry.shared.remove(screenFrame: window.frame)
        }
        windows.forEach { $0.close() }
        windows.removeAll()
        removePassthroughUpdater()
    }

    private func installPassthroughUpdater() {
        removePassthroughUpdater()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMousePassthrough()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }
        framesObserver = NotificationCenter.default.addObserver(
            forName: .overlayInteractionFramesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMousePassthrough()
        }
    }

    private func removePassthroughUpdater() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let framesObserver {
            NotificationCenter.default.removeObserver(framesObserver)
            self.framesObserver = nil
        }
    }

    private func updateMousePassthrough() {
        let globalPoint = NSEvent.mouseLocation
        for window in windows {
            let frame = window.frame
            guard frame.contains(globalPoint) else {
                window.ignoresMouseEvents = true
                continue
            }

            let localPoint = CGPoint(
                x: globalPoint.x - frame.minX,
                y: frame.height - (globalPoint.y - frame.minY)
            )
            let shouldAcceptMouse = OverlayInteractionRegistry.shared.contains(screenFrame: frame, point: localPoint)
            window.ignoresMouseEvents = !shouldAcceptMouse
        }
    }
}
