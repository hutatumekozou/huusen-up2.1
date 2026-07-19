import SwiftUI
import AppKit
import AVFoundation

private enum AnswerControlFrame: Hashable {
    case correctStamp
    case incorrectStamp
    case correctEdit
    case incorrectEdit
    case correctMinus
    case correctPlus
    case incorrectMinus
    case incorrectPlus
    case reviewUpdate
    case localCheck
}

private let minimumOverlayZoom = 0.5
private let maximumOverlayZoom = 3.0

struct BalloonOverlayView: View {
    let settings: OverlaySettings
    let screenFrame: CGRect
    let onFinished: () -> Void

    @State private var xRatio = 0.5
    @State private var yPosition: Double?
    @State private var balloonHitFrame = CGRect.zero
    @State private var imageHitFrame = CGRect.zero
    @State private var backBadgeFrame = CGRect.zero
    @State private var triangleHitFrame = CGRect.zero
    @State private var explanationButtonFrame = CGRect.zero
    @State private var explanationBubbleFrame = CGRect.zero
    @State private var explanationScrollAreaFrame = CGRect.zero
    @State private var closeButtonFrame = CGRect.zero
    @State private var correctStampFrame = CGRect.zero
    @State private var incorrectStampFrame = CGRect.zero
    @State private var correctEditFrame = CGRect.zero
    @State private var incorrectEditFrame = CGRect.zero
    @State private var correctMinusFrame = CGRect.zero
    @State private var correctPlusFrame = CGRect.zero
    @State private var incorrectMinusFrame = CGRect.zero
    @State private var incorrectPlusFrame = CGRect.zero
    @State private var reviewUpdateFrame = CGRect.zero
    @State private var localCheckFrame = CGRect.zero
    @State private var explanationImageFrames: [Int: CGRect] = [:]
    @State private var imagePreviewFrame = CGRect.zero
    @State private var imagePreviewCloseFrame = CGRect.zero
    @State private var imagePreviewZoomOutFrame = CGRect.zero
    @State private var imagePreviewZoomInFrame = CGRect.zero
    @State private var previewImage: NSImage?
    @State private var imagePreviewZoom = 1.0
    @State private var imagePreviewOffset = CGSize.zero
    @State private var isImagePreviewDragging = false
    @State private var imagePreviewDragStart = CGPoint.zero
    @State private var imagePreviewLastOffset = CGSize.zero
    @State private var explanationZoom = 1.0
    @State private var explanationZoomOutFrame = CGRect.zero
    @State private var explanationZoomInFrame = CGRect.zero
    @State private var isPausedAtMiddle = false
    @State private var isShowingExplanation = false
    @State private var isShowingImagePreview = false
    @State private var didFinish = false
    @State private var motionTimer: Timer?
    @State private var lastTickDate: Date?
    @State private var middlePauseRemaining: Double?
    @State private var hasReachedMiddle = false
    @State private var didSpeakAtMiddle = false
    @State private var isShowingBack = false
    @State private var localCheckCount = 0
    @State private var motionEndY = 0.0
    @State private var motionMiddleY = 0.0
    @State private var motionCenterX = 0.0
    @State private var motionBalloonSize = 0.0
    @State private var motionContainerSize = CGSize.zero
    @State private var clickObserver: NSObjectProtocol?
    @State private var scrollObserver: NSObjectProtocol?
    @State private var dragObserver: NSObjectProtocol?
    @State private var answerRevision = 0
    @State private var answerFeedback: String?
    @State private var editingAnswerCount: Bool?
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        GeometryReader { proxy in
            let balloon = settings.activeBalloon
            let standardBalloonSize = min(max(proxy.size.width * 0.14, 120), 180)
            let requestedBalloonSize = standardBalloonSize * balloon.sizeScale
            let balloonSize = fittedBalloonSize(requestedBalloonSize, containerSize: proxy.size)
            let contentScale = max(0.8, balloonSize / standardBalloonSize)
            let centerX = fittedCenterX(for: xRatio, balloonSize: balloonSize, containerWidth: proxy.size.width)
            let startY = proxy.size.height + balloonSize
            let endY = -balloonSize
            let middleY = proxy.size.height / 2
            let currentY = yPosition ?? startY
            let explanationText = balloon.explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasExplanation = !explanationText.isEmpty || !balloon.explanationImageDataURLs.isEmpty
            let startsVisible = balloon.genreName == "Codex通知" || balloon.middlePauseDuration >= 999

            ZStack {
                balloonView(
                    size: balloonSize,
                    contentScale: contentScale,
                    balloon: balloon,
                    isShowingBack: isShowingBack,
                    hasExplanation: hasExplanation
                )
                    .position(x: centerX, y: currentY)

                if isShowingExplanation {
                    explanationBubbleView(text: explanationText)
                        .frame(width: explanationBubbleFrame.width, height: explanationBubbleFrame.height)
                        .position(x: explanationBubbleFrame.midX, y: explanationBubbleFrame.midY)
                }

                if isShowingImagePreview, let previewImage {
                    imagePreviewView(image: previewImage)
                        .frame(width: imagePreviewFrame.width, height: imagePreviewFrame.height)
                        .position(x: imagePreviewFrame.midX, y: imagePreviewFrame.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "overlayRoot")
            .background(Color.clear)
            .onAppear {
                let initialY = startsVisible ? middleY : startY
                xRatio = resolvedXRatio(for: balloon)
                yPosition = initialY
                motionEndY = endY
                motionMiddleY = middleY
                motionCenterX = centerX
                motionBalloonSize = balloonSize
                motionContainerSize = proxy.size
                didSpeakAtMiddle = false
                if startsVisible {
                    hasReachedMiddle = true
                    isPausedAtMiddle = true
                    middlePauseRemaining = pauseRemaining(for: balloon)
                    speakAtMiddleIfNeeded(for: balloon)
                }
                updateInteractionFrames(centerX: centerX, centerY: initialY, size: balloonSize, containerSize: proxy.size)
                isShowingBack = false
                localCheckCount = savedLocalCheckCount(for: balloon)
                installClickObserver()
                startMotionTimer()
            }
            .onChange(of: yPosition ?? startY) { _, newY in
                updateInteractionFrames(centerX: centerX, centerY: newY, size: balloonSize, containerSize: proxy.size)
            }
            .onChange(of: isShowingExplanation) { _, _ in
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onChange(of: isShowingImagePreview) { _, _ in
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onChange(of: balloon.id) { _, _ in
                localCheckCount = savedLocalCheckCount(for: balloon)
            }
            .onPreferenceChange(ExplanationImageFramePreferenceKey.self) { frames in
                explanationImageFrames = frames
            }
            .onPreferenceChange(ExplanationScrollAreaPreferenceKey.self) { frame in
                explanationScrollAreaFrame = frame
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onPreferenceChange(ExplanationCloseButtonPreferenceKey.self) { frame in
                closeButtonFrame = frame
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onPreferenceChange(ExplanationZoomOutButtonPreferenceKey.self) { frame in
                explanationZoomOutFrame = zoomButtonHitFrame(for: frame)
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onPreferenceChange(ExplanationZoomInButtonPreferenceKey.self) { frame in
                explanationZoomInFrame = zoomButtonHitFrame(for: frame)
                updateInteractionFrames(centerX: centerX, centerY: currentY, size: balloonSize, containerSize: proxy.size)
            }
            .onPreferenceChange(AnswerControlFramePreferenceKey.self) { frames in
                correctStampFrame = frames[.correctStamp] ?? .zero
                incorrectStampFrame = frames[.incorrectStamp] ?? .zero
                correctEditFrame = frames[.correctEdit] ?? .zero
                incorrectEditFrame = frames[.incorrectEdit] ?? .zero
                correctMinusFrame = frames[.correctMinus] ?? .zero
                correctPlusFrame = frames[.correctPlus] ?? .zero
                incorrectMinusFrame = frames[.incorrectMinus] ?? .zero
                incorrectPlusFrame = frames[.incorrectPlus] ?? .zero
                reviewUpdateFrame = frames[.reviewUpdate] ?? .zero
                localCheckFrame = frames[.localCheck] ?? .zero
            }
            .onDisappear {
                speechSynthesizer.stopSpeaking(at: .immediate)
                stopMotionTimer()
                removeClickObserver()
                OverlayInteractionRegistry.shared.remove(screenFrame: screenFrame)
            }
        }
    }

    private func startMotionTimer() {
        stopMotionTimer()
        lastTickDate = Date()
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            tickMotion()
        }
    }

    private func stopMotionTimer() {
        motionTimer?.invalidate()
        motionTimer = nil
        lastTickDate = nil
    }

    private func speakAtMiddleIfNeeded(for balloon: BalloonProfile) {
        guard settings.isSpeechOutputEnabled else { return }

        let speechText = balloon.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !didSpeakAtMiddle, !speechText.isEmpty else { return }

        didSpeakAtMiddle = true
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: speechText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.volume = Float(settings.speechVolume)
        speechSynthesizer.speak(utterance)
    }

    private var shouldWaitForSpeechBeforeLeavingMiddle: Bool {
        didSpeakAtMiddle && speechSynthesizer.isSpeaking
    }

    private func tickMotion() {
        guard !didFinish else { return }

        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastTickDate ?? now), 0), 0.08)
        lastTickDate = now

        guard !isShowingExplanation, !isShowingImagePreview else { return }

        if let remaining = middlePauseRemaining {
            let nextRemaining = remaining - delta
            if nextRemaining > 0 {
                middlePauseRemaining = nextRemaining
                return
            }
            if shouldWaitForSpeechBeforeLeavingMiddle {
                middlePauseRemaining = 0
                isPausedAtMiddle = true
                return
            }
            middlePauseRemaining = nil
            isPausedAtMiddle = false
        }

        guard let currentY = yPosition else { return }

        let nextY = currentY - settings.climbSpeed * delta
        let balloon = settings.activeBalloon
        if balloon.pausesAtMiddle, !hasReachedMiddle, nextY <= motionMiddleY {
            yPosition = motionMiddleY
            hasReachedMiddle = true
            isPausedAtMiddle = true
            middlePauseRemaining = pauseRemaining(for: balloon)
            speakAtMiddleIfNeeded(for: balloon)
            return
        }

        yPosition = nextY
        if nextY <= motionEndY {
            didFinish = true
            stopMotionTimer()
            removeClickObserver()
            OverlayInteractionRegistry.shared.remove(screenFrame: screenFrame)
            onFinished()
        }
    }

    private func installClickObserver() {
        if clickObserver == nil {
            clickObserver = NotificationCenter.default.addObserver(
                forName: .overlayClick,
                object: nil,
                queue: .main
            ) { notification in
                guard let click = notification.object as? OverlayClick,
                      OverlayInteractionRegistry.shared.sameScreen(click.screenFrame, screenFrame) else {
                    return
                }
                handleClick(at: click.point)
            }
        }

        if scrollObserver == nil {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: .overlayScroll,
                object: nil,
                queue: .main
            ) { notification in
                guard let scroll = notification.object as? OverlayScroll,
                      OverlayInteractionRegistry.shared.sameScreen(scroll.screenFrame, screenFrame) else {
                    return
                }
                handleImagePreviewScroll(deltaX: scroll.deltaX, deltaY: scroll.deltaY)
            }
        }

        if dragObserver == nil {
            dragObserver = NotificationCenter.default.addObserver(
                forName: .overlayDrag,
                object: nil,
                queue: .main
            ) { notification in
                guard let drag = notification.object as? OverlayDrag,
                      OverlayInteractionRegistry.shared.sameScreen(drag.screenFrame, screenFrame) else {
                    return
                }
                handleImagePreviewDrag(drag)
            }
        }

    }

    private func removeClickObserver() {
        if let clickObserver {
            NotificationCenter.default.removeObserver(clickObserver)
            self.clickObserver = nil
        }
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        if let dragObserver {
            NotificationCenter.default.removeObserver(dragObserver)
            self.dragObserver = nil
        }
    }

    private func handleClick(at localPoint: CGPoint) {
        if isShowingImagePreview {
            if imagePreviewZoomOutFrame.contains(localPoint) {
                imagePreviewZoom = max(minimumOverlayZoom, imagePreviewZoom - 0.15)
                if imagePreviewZoom <= 1 {
                    imagePreviewOffset = .zero
                    imagePreviewLastOffset = .zero
                } else {
                    imagePreviewOffset = clampedImagePreviewOffset(imagePreviewOffset)
                    imagePreviewLastOffset = imagePreviewOffset
                }
                return
            }
            if imagePreviewZoomInFrame.contains(localPoint) {
                imagePreviewZoom = min(maximumOverlayZoom, imagePreviewZoom + 0.15)
                imagePreviewOffset = clampedImagePreviewOffset(imagePreviewOffset)
                imagePreviewLastOffset = imagePreviewOffset
                return
            }
            if imagePreviewCloseFrame.contains(localPoint) {
                isShowingImagePreview = false
                previewImage = nil
                imagePreviewZoom = 1.0
                imagePreviewOffset = .zero
                imagePreviewLastOffset = .zero
                isImagePreviewDragging = false
            }
            return
        }

        if isShowingExplanation {
            let handlesAnswerControls = settings.activeBalloon.genreName != "Codex通知"
            if explanationZoomOutFrame.contains(localPoint) {
                explanationZoom = max(minimumOverlayZoom, explanationZoom - 0.15)
                return
            }
            if explanationZoomInFrame.contains(localPoint) {
                explanationZoom = min(maximumOverlayZoom, explanationZoom + 0.15)
                return
            }
            if closeButtonFrame.contains(localPoint) {
                isShowingExplanation = false
                editingAnswerCount = nil
                explanationImageFrames = [:]
                resetExplanationViewportState()
                return
            }
            if localCheckFrame.contains(localPoint) {
                incrementLocalCheckCount()
                return
            }
            if handlesAnswerControls, editingAnswerCount == true, correctMinusFrame.contains(localPoint) {
                adjustAnswerCount(isCorrect: true, delta: -1)
                return
            }
            if handlesAnswerControls, editingAnswerCount == true, correctPlusFrame.contains(localPoint) {
                adjustAnswerCount(isCorrect: true, delta: 1)
                return
            }
            if handlesAnswerControls, editingAnswerCount == false, incorrectMinusFrame.contains(localPoint) {
                adjustAnswerCount(isCorrect: false, delta: -1)
                return
            }
            if handlesAnswerControls, editingAnswerCount == false, incorrectPlusFrame.contains(localPoint) {
                adjustAnswerCount(isCorrect: false, delta: 1)
                return
            }
            if handlesAnswerControls, correctEditFrame.contains(localPoint) {
                editingAnswerCount = editingAnswerCount == true ? nil : true
                answerRevision += 1
                return
            }
            if handlesAnswerControls, incorrectEditFrame.contains(localPoint) {
                editingAnswerCount = editingAnswerCount == false ? nil : false
                answerRevision += 1
                return
            }
            if handlesAnswerControls, reviewUpdateFrame.contains(localPoint) {
                saveAnswerReview()
                return
            }
            if handlesAnswerControls, correctStampFrame.contains(localPoint) {
                recordAnswer(isCorrect: true)
                return
            }
            if handlesAnswerControls, incorrectStampFrame.contains(localPoint) {
                recordAnswer(isCorrect: false)
                return
            }
            if let image = explanationImage(at: localPoint) {
                openImagePreview(image)
            }
            return
        }

        if explanationButtonFrame.contains(localPoint),
           settings.activeBalloon.hasExplanation {
            resetExplanationViewportState()
            isShowingExplanation = true
            return
        }

        if backBadgeFrame.contains(localPoint), settings.activeBalloon.hasBackSide {
            isShowingBack.toggle()
            middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
            isPausedAtMiddle = true
            return
        }

        if imageHitFrame.contains(localPoint), let image = activeDisplayImage(for: settings.activeBalloon) {
            openImagePreview(image)
            middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
            isPausedAtMiddle = true
            return
        }

        if triangleHitFrame.contains(localPoint) {
            manuallyReleaseMiddlePause()
            return
        }

        if balloonHitFrame.contains(localPoint) {
            if settings.activeBalloon.middlePauseDuration >= 999 {
                manuallyReleaseMiddlePause()
                return
            }
            middlePauseRemaining = max(middlePauseRemaining ?? 0, 2)
            isPausedAtMiddle = true
        }
    }

    private func pauseRemaining(for balloon: BalloonProfile) -> Double {
        balloon.middlePauseDuration >= 999 ? Double.greatestFiniteMagnitude : min(max(balloon.middlePauseDuration, 0.1), 30)
    }

    private func manuallyReleaseMiddlePause() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        middlePauseRemaining = nil
        isPausedAtMiddle = false
    }

    private func openImagePreview(_ image: NSImage) {
        previewImage = image
        imagePreviewZoom = 1.0
        imagePreviewOffset = .zero
        imagePreviewLastOffset = .zero
        isImagePreviewDragging = false
        isShowingImagePreview = true
    }

    private func handleImagePreviewScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard isShowingImagePreview, imagePreviewZoom > 1 else { return }

        let nextOffset = CGSize(
            width: imagePreviewOffset.width - deltaX,
            height: imagePreviewOffset.height + deltaY
        )
        imagePreviewOffset = clampedImagePreviewOffset(nextOffset)
        imagePreviewLastOffset = imagePreviewOffset
    }

    private func handleImagePreviewDrag(_ drag: OverlayDrag) {
        guard isShowingImagePreview, imagePreviewZoom > 1 else {
            isImagePreviewDragging = false
            return
        }

        switch drag.phase {
        case .began:
            guard !imagePreviewCloseFrame.contains(drag.point),
                  !imagePreviewZoomOutFrame.contains(drag.point),
                  !imagePreviewZoomInFrame.contains(drag.point) else {
                isImagePreviewDragging = false
                return
            }
            isImagePreviewDragging = true
            imagePreviewDragStart = drag.point
            imagePreviewLastOffset = imagePreviewOffset
        case .changed:
            guard isImagePreviewDragging else { return }
            let nextOffset = CGSize(
                width: imagePreviewLastOffset.width + drag.point.x - imagePreviewDragStart.x,
                height: imagePreviewLastOffset.height + drag.point.y - imagePreviewDragStart.y
            )
            imagePreviewOffset = clampedImagePreviewOffset(nextOffset)
        case .ended, .cancelled:
            isImagePreviewDragging = false
            imagePreviewLastOffset = imagePreviewOffset
        }
    }

    private func clampedImagePreviewOffset(_ offset: CGSize) -> CGSize {
        let overflow = max(0, imagePreviewZoom - 1)
        let maxX = imagePreviewFrame.width * overflow * 0.55
        let maxY = imagePreviewFrame.height * overflow * 0.55

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func resetExplanationViewportState() {
        explanationZoom = 1.0
        explanationZoomOutFrame = .zero
        explanationZoomInFrame = .zero
    }

    private func zoomButtonHitFrame(for visualFrame: CGRect) -> CGRect {
        visualFrame
            .insetBy(dx: -34, dy: -34)
            .offsetBy(dx: 0, dy: -32)
    }

    private func updateInteractionFrames(centerX: Double, centerY: Double, size: Double, containerSize: CGSize) {
        let hitWidth = size * 1.15
        let hitHeight = size * 1.75
        let circleCenterY = centerY - size * 0.33
        balloonHitFrame = CGRect(
            x: centerX - hitWidth / 2,
            y: centerY - hitHeight / 2,
            width: hitWidth,
            height: hitHeight
        )
        imageHitFrame = CGRect(
            x: centerX - size * 0.41,
            y: circleCenterY - size * 0.41,
            width: size * 0.82,
            height: size * 0.82
        )
        let badgeWidth = max(45, 43 * settings.activeBalloon.sizeScale)
        let badgeHeight = max(20, 20 * settings.activeBalloon.sizeScale)
        let explanationWidth = 64.0
        let explanationHeight = 30.0
        let badgeGap = 4.0
        let hasBackBadge = settings.activeBalloon.hasBackSide
        let hasExplanationButton = settings.activeBalloon.hasExplanation
        let badgeRowWidth = (hasBackBadge ? badgeWidth : 0)
            + (hasBackBadge && hasExplanationButton ? badgeGap : 0)
            + (hasExplanationButton ? explanationWidth : 0)
        let badgeRowCenterY = circleCenterY - size * 0.38
        let badgeRowMinX = centerX - badgeRowWidth / 2
        backBadgeFrame = CGRect(
            x: hasBackBadge ? badgeRowMinX : 0,
            y: hasBackBadge ? badgeRowCenterY - badgeHeight / 2 : 0,
            width: hasBackBadge ? badgeWidth : 0,
            height: hasBackBadge ? badgeHeight : 0
        )
        triangleHitFrame = CGRect(
            x: centerX - size * 0.18,
            y: circleCenterY + size * 0.40,
            width: size * 0.36,
            height: size * 0.26
        )

        explanationButtonFrame = CGRect(
            x: hasExplanationButton ? badgeRowMinX + (hasBackBadge ? badgeWidth + badgeGap : 0) : 0,
            y: hasExplanationButton ? badgeRowCenterY - explanationHeight / 2 : 0,
            width: hasExplanationButton ? explanationWidth : 0,
            height: hasExplanationButton ? explanationHeight : 0
        )

        let bubbleWidth = min(max(containerSize.width * 0.76, 520), min(1200, containerSize.width - 40))
        let bubbleHeight = min(max(containerSize.height * 0.90, 360), containerSize.height - 40)
        let bubbleX = min(max(centerX + size * 0.62 + bubbleWidth / 2, bubbleWidth / 2 + 20), containerSize.width - bubbleWidth / 2 - 20)
        let bubbleY = min(max(centerY - size * 0.12, bubbleHeight / 2 + 20), containerSize.height - bubbleHeight / 2 - 20)
        explanationBubbleFrame = CGRect(
            x: bubbleX - bubbleWidth / 2,
            y: bubbleY - bubbleHeight / 2,
            width: bubbleWidth,
            height: bubbleHeight
        )
        closeButtonFrame = CGRect(
            x: explanationBubbleFrame.maxX - 94,
            y: explanationBubbleFrame.maxY - 48,
            width: 74,
            height: 32
        )
        let fallbackExplanationZoomInFrame = CGRect(
            x: explanationBubbleFrame.maxX - 64,
            y: explanationBubbleFrame.minY + 14,
            width: 48,
            height: 48
        )
        if explanationZoomInFrame == .zero {
            explanationZoomInFrame = zoomButtonHitFrame(for: fallbackExplanationZoomInFrame)
        }
        if explanationZoomOutFrame == .zero {
            explanationZoomOutFrame = zoomButtonHitFrame(for: CGRect(
                x: fallbackExplanationZoomInFrame.minX - 58,
                y: explanationBubbleFrame.minY + 14,
                width: 48,
                height: 48
            ))
        }
        let stampGap = 12.0
        let stampHeight = 56.0
        let stampWidth = max(120, (explanationBubbleFrame.width - 36 - stampGap) / 2)
        let stampY = explanationBubbleFrame.maxY - 118
        correctStampFrame = CGRect(
            x: explanationBubbleFrame.minX + 18,
            y: stampY,
            width: stampWidth,
            height: stampHeight
        )
        incorrectStampFrame = CGRect(
            x: explanationBubbleFrame.minX + 18 + stampWidth + stampGap,
            y: stampY,
            width: stampWidth,
            height: stampHeight
        )
        correctEditFrame = answerEditFrame(in: correctStampFrame)
        incorrectEditFrame = answerEditFrame(in: incorrectStampFrame)

        let previewWidth = min(max(containerSize.width * 0.66, 460), 980)
        let previewHeight = min(max(containerSize.height * 0.66, 360), 760)
        imagePreviewFrame = CGRect(
            x: (containerSize.width - previewWidth) / 2,
            y: (containerSize.height - previewHeight) / 2,
            width: previewWidth,
            height: previewHeight
        )
        imagePreviewCloseFrame = CGRect(
            x: imagePreviewFrame.maxX - 94,
            y: imagePreviewFrame.minY + 16,
            width: 74,
            height: 48
        )
        let imagePreviewZoomInVisualFrame = CGRect(
            x: imagePreviewCloseFrame.minX - 58,
            y: imagePreviewFrame.minY + 16,
            width: 48,
            height: 48
        )
        let imagePreviewZoomOutVisualFrame = CGRect(
            x: imagePreviewZoomInVisualFrame.minX - 58,
            y: imagePreviewFrame.minY + 16,
            width: 48,
            height: 48
        )
        imagePreviewZoomInFrame = zoomButtonHitFrame(for: imagePreviewZoomInVisualFrame)
        imagePreviewZoomOutFrame = zoomButtonHitFrame(for: imagePreviewZoomOutVisualFrame)

        OverlayInteractionRegistry.shared.update(
            screenFrame: screenFrame,
            frames: OverlayInteractionFrames(
                balloon: balloonHitFrame,
                image: imageHitFrame,
                backBadge: backBadgeFrame,
                triangle: triangleHitFrame,
                explanationButton: explanationButtonFrame,
                explanationBubble: explanationBubbleFrame,
                explanationScrollArea: explanationScrollAreaFrame,
                explanationCloseButton: closeButtonFrame,
                explanationZoomOutButton: explanationZoomOutFrame,
                explanationZoomInButton: explanationZoomInFrame,
                imagePreview: imagePreviewFrame,
                isShowingExplanation: isShowingExplanation,
                isShowingImagePreview: isShowingImagePreview
            )
        )
    }

    private func explanationImage(at point: CGPoint) -> NSImage? {
        let images = settings.activeBalloon.explanationImages
        guard !images.isEmpty else { return nil }

        return explanationImageFrames
            .sorted { $0.key < $1.key }
            .first { $0.value.contains(point) }
            .flatMap { images[safe: $0.key] }
    }

    private func recordAnswer(isCorrect: Bool) {
        let id = settings.activeBalloon.id
        settings.recordAnswer(for: id, isCorrect: isCorrect)
        editingAnswerCount = nil
        answerRevision += 1
        answerFeedback = isCorrect ? "正解を記録しました" : "不正解を記録しました"
        middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
        isPausedAtMiddle = true
    }

    private func adjustAnswerCount(isCorrect: Bool, delta: Int) {
        let id = settings.activeBalloon.id
        settings.adjustAnswerCount(for: id, isCorrect: isCorrect, delta: delta)
        answerRevision += 1
        let label = isCorrect ? "正解" : "不正解"
        answerFeedback = delta > 0 ? "\(label)数を1増やしました" : "\(label)数を1減らしました"
        middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
        isPausedAtMiddle = true
    }

    private func saveAnswerReview() {
        let id = settings.activeBalloon.id
        settings.saveAnswerReview(for: id)
        editingAnswerCount = nil
        answerRevision += 1
        answerFeedback = "更新しました \(formatReviewTimestamp(Date()))"
        middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
        isPausedAtMiddle = true
    }

    private func savedLocalCheckCount(for balloon: BalloonProfile) -> Int {
        let counts = UserDefaults.standard.dictionary(forKey: "huusenBalloonOverlayPCCheckCounts") ?? [:]
        let value = counts[localCheckCountKey(for: balloon)] as? Int ?? 0
        return max(0, value)
    }

    private func incrementLocalCheckCount() {
        let balloon = settings.activeBalloon
        let key = localCheckCountKey(for: balloon)
        var counts = UserDefaults.standard.dictionary(forKey: "huusenBalloonOverlayPCCheckCounts") ?? [:]
        let nextCount = savedLocalCheckCount(for: balloon) + 1
        counts[key] = nextCount
        UserDefaults.standard.set(counts, forKey: "huusenBalloonOverlayPCCheckCounts")
        localCheckCount = nextCount
        answerFeedback = "チェックを記録しました"
        middlePauseRemaining = max(middlePauseRemaining ?? 0, 6)
        isPausedAtMiddle = true
    }

    private func localCheckCountKey(for balloon: BalloonProfile) -> String {
        balloon.itemNumber > 0 ? "item-\(balloon.itemNumber)" : balloon.id.uuidString
    }

    private func formatReviewTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private func answerStepperFrame(in stampFrame: CGRect, slot: Int) -> CGRect {
        CGRect(
            x: stampFrame.maxX - 86 + Double(slot) * 40,
            y: stampFrame.midY - 16,
            width: 34,
            height: 32
        )
    }

    private func answerEditFrame(in stampFrame: CGRect) -> CGRect {
        CGRect(
            x: stampFrame.maxX - 78,
            y: stampFrame.midY - 16,
            width: 66,
            height: 32
        )
    }

    private func resolvedXRatio(for balloon: BalloonProfile) -> Double {
        let positionName = balloon.middlePauseDuration >= 999 ? balloon.positionName : settings.launchPositionName
        if positionName == "ランダム" {
            return OverlaySettings.positionOptions.compactMap { $0.ratio }.randomElement() ?? 0.5
        }

        return OverlaySettings.positionOptions.first(where: { $0.name == positionName })?.ratio ?? 0.5
    }

    private func fittedBalloonSize(_ requestedSize: Double, containerSize: CGSize) -> Double {
        let maxWidth = max(120, containerSize.width * 0.86)
        let maxHeight = max(120, containerSize.height / 1.72)
        return min(requestedSize, maxWidth, maxHeight)
    }

    private func fittedCenterX(for ratio: Double, balloonSize: Double, containerWidth: Double) -> Double {
        let minX = balloonSize * 0.72
        let maxX = max(containerWidth - balloonSize * 0.72, minX)
        let rawCenterX = minX + (maxX - minX) * ratio
        let visibleMinX = min(containerWidth / 2, balloonSize * 0.52)
        let visibleMaxX = max(visibleMinX, containerWidth - balloonSize * 0.52)
        return min(max(rawCenterX, visibleMinX), visibleMaxX)
    }

    private func explanationButtonView(contentScale: Double = 1) -> some View {
        Text("解説")
            .font(.system(size: max(12, 13 * contentScale), weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
    }

    private func explanationBubbleView(text: String) -> some View {
        let balloon = settings.activeBalloon
        let bodyFontSize: CGFloat = text.count > 180 ? 15 : 18
        let images = balloon.explanationImages
        let correctCount = balloon.correctCount
        let incorrectCount = balloon.incorrectCount
        let checkCount = self.localCheckCount
        let showsAnswerControls = balloon.genreName != "Codex通知"
        let reviewText = balloon.lastReviewedAt.map { "前回の更新時: \(formatReviewTimestamp($0))" } ?? "前回の更新時: 未保存"
        let _ = answerRevision

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                explanationHeader()
                    .fixedSize(horizontal: false, vertical: true)

                explanationScrollableContent(text: text, bodyFontSize: bodyFontSize, images: images)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .layoutPriority(1)

                explanationFooter(
                    correctCount: correctCount,
                    incorrectCount: incorrectCount,
                    localCheckCount: checkCount,
                    reviewText: reviewText,
                    showsAnswerControls: showsAnswerControls
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                explanationZoomButton(symbol: "-")
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExplanationZoomOutButtonPreferenceKey.self,
                                value: geometry.frame(in: .named("overlayRoot"))
                            )
                        }
                    )
                explanationZoomButton(symbol: "+")
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExplanationZoomInButtonPreferenceKey.self,
                                value: geometry.frame(in: .named("overlayRoot"))
                            )
                        }
                    )
            }
            .padding(.top, 14)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 8)
    }

    private func explanationHeader() -> some View {
        Text("解説")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.trailing, 128)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    private func explanationScrollableContent(text: String, bodyFontSize: CGFloat, images: [NSImage]) -> some View {
        GeometryReader { viewportGeometry in
            AlwaysVisibleVerticalScrollView {
                explanationBodyContent(text: text, bodyFontSize: bodyFontSize, images: images)
                    .frame(width: max(1, viewportGeometry.size.width - 16), alignment: .leading)
            }
            .frame(width: viewportGeometry.size.width, height: viewportGeometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)
            }
            .preference(
                key: ExplanationScrollAreaPreferenceKey.self,
                value: viewportGeometry.frame(in: .named("overlayRoot"))
            )
        }
        .accessibilityIdentifier("explanation-pan-body")
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }

    private func explanationBodyContent(text: String, bodyFontSize: CGFloat, images: [NSImage]) -> some View {
        let scaledBodyFontSize = min(42, max(11, bodyFontSize * explanationZoom))
        let imageMinHeight = min(360, max(100, 120 * explanationZoom))
        let imageMaxHeight = min(520, max(140, 220 * explanationZoom))

        return VStack(alignment: .leading, spacing: 14) {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: scaledBodyFontSize, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .lineSpacing(6 * explanationZoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !images.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: imageMinHeight, maxHeight: imageMaxHeight)
                            .padding(8)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openImagePreview(image)
                            }
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ExplanationImageFramePreferenceKey.self,
                                        value: [index: geometry.frame(in: .named("overlayRoot"))]
                                    )
                                }
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.trailing, 32)
        .padding(.bottom, 18)
    }

    private func explanationFooter(
        correctCount: Int,
        incorrectCount: Int,
        localCheckCount: Int,
        reviewText: String,
        showsAnswerControls: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsAnswerControls {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        answerStampView(
                            face: "😺",
                            title: "わかった",
                            subtitle: "正解 \(correctCount)",
                            tint: Color(red: 0.10, green: 0.55, blue: 0.28),
                            isEditing: editingAnswerCount == true,
                            isCorrect: true
                        )
                        answerStampView(
                            face: "😿",
                            title: "忘れてた",
                            subtitle: "不正解 \(incorrectCount)",
                            tint: Color(red: 0.74, green: 0.20, blue: 0.18),
                            isEditing: editingAnswerCount == false,
                            isCorrect: false
                        )
                    }
                    if let answerFeedback {
                        Text(answerFeedback)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if showsAnswerControls {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reviewText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.58))
                        Text("更新")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 92, height: 32)
                            .background(Color(red: 0.12, green: 0.45, blue: 0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: AnswerControlFramePreferenceKey.self,
                                        value: [.reviewUpdate: geometry.frame(in: .named("overlayRoot"))]
                                    )
                                }
                            )
                    }
                }
                Spacer()
                localCheckCountView(count: localCheckCount)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: AnswerControlFramePreferenceKey.self,
                                value: [.localCheck: geometry.frame(in: .named("overlayRoot"))]
                            )
                        }
                    )
                Text("閉じる")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 32)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExplanationCloseButtonPreferenceKey.self,
                                value: geometry.frame(in: .named("overlayRoot"))
                            )
                        }
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -3))
    }

    private func localCheckCountView(count: Int) -> some View {
        HStack(spacing: 5) {
            Text("🌟")
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.system(size: 16, weight: .heavy))
        .foregroundStyle(Color(red: 0.52, green: 0.33, blue: 0))
        .frame(minWidth: 66)
        .frame(height: 32)
        .background(Color(red: 1.0, green: 0.94, blue: 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.90, green: 0.63, blue: 0.05), lineWidth: 1.2))
        .accessibilityLabel("PCのチェック回数。現在 \(count) 回")
    }

    private func answerStampView(face: String, title: String, subtitle: String, tint: Color, isEditing: Bool, isCorrect: Bool) -> some View {
        let stampFrameKey: AnswerControlFrame = isCorrect ? .correctStamp : .incorrectStamp
        let editFrameKey: AnswerControlFrame = isCorrect ? .correctEdit : .incorrectEdit
        let minusFrameKey: AnswerControlFrame = isCorrect ? .correctMinus : .incorrectMinus
        let plusFrameKey: AnswerControlFrame = isCorrect ? .correctPlus : .incorrectPlus

        return HStack(spacing: 10) {
            Text(face)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
                Text(subtitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
            if isEditing {
                HStack(spacing: 6) {
                    Text("-")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 34, height: 32)
                        .background(Color.white.opacity(0.74))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.35), lineWidth: 1))
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: AnswerControlFramePreferenceKey.self,
                                    value: [minusFrameKey: geometry.frame(in: .named("overlayRoot"))]
                                )
                            }
                        )
                    Text("+")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 34, height: 32)
                        .background(Color.white.opacity(0.74))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.35), lineWidth: 1))
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: AnswerControlFramePreferenceKey.self,
                                    value: [plusFrameKey: geometry.frame(in: .named("overlayRoot"))]
                                )
                            }
                        )
                }
                .foregroundStyle(tint)
            } else {
                Text("修正")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 66, height: 32)
                    .background(Color.white.opacity(0.74))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.35), lineWidth: 1))
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: AnswerControlFramePreferenceKey.self,
                                value: [editFrameKey: geometry.frame(in: .named("overlayRoot"))]
                            )
                        }
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35), lineWidth: 1.4))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AnswerControlFramePreferenceKey.self,
                    value: [stampFrameKey: geometry.frame(in: .named("overlayRoot"))]
                )
            }
        )
    }

    private func imagePreviewView(image: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.82)

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(imagePreviewZoom)
                .offset(imagePreviewOffset)
                .padding(.leading, 28)
                .padding(.vertical, 28)
                .padding(.trailing, 148)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            HStack(spacing: 10) {
                previewZoomButton(symbol: "-")
                previewZoomButton(symbol: "+")
                Text("閉じる")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 32)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
                .padding(.top, 16)
                .padding(.trailing, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.34), radius: 22, x: 0, y: 10)
    }

    private func previewZoomButton(symbol: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 4)
                .frame(width: 31, height: 31)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 18, height: 5)
                        .clipShape(Capsule())
                        .rotationEffect(.degrees(45))
                        .offset(x: 16, y: 16)
                )

            Text(symbol)
                .font(.system(size: 29, weight: .heavy))
                .foregroundStyle(.white)
                .offset(x: -1, y: -2)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
    }

    private func explanationZoomButton(symbol: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.88), lineWidth: 4)
                .frame(width: 31, height: 31)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.88))
                        .frame(width: 18, height: 5)
                        .clipShape(Capsule())
                        .rotationEffect(.degrees(45))
                        .offset(x: 16, y: 16)
                )

            Text(symbol)
                .font(.system(size: 29, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.88))
                .offset(x: -1, y: -2)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
    }

    private func activeDisplayImage(for balloon: BalloonProfile) -> NSImage? {
        if isShowingBack {
            return balloon.attachedBackImage ?? balloon.assetBackImage
        }

        return balloon.attachedImage ?? balloon.assetImage
    }

    private func balloonView(
        size: Double,
        contentScale: Double,
        balloon: BalloonProfile,
        isShowingBack: Bool,
        hasExplanation: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if balloon.colorName == OverlaySettings.customBalloonDesignName,
                   let customBalloonDesign = balloon.attachedCustomBalloonDesign {
                    Image(nsImage: customBalloonDesign)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .scaleEffect(balloon.customBalloonDesignScale)
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                        .zIndex(0)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: balloon.colorStartHex),
                                    Color(hex: balloon.colorEndHex)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 2))
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)

                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size * 0.22, height: size * 0.22)
                        .offset(x: -size * 0.19, y: -size * 0.18)
                }

                contentView(for: balloon, isShowingBack: isShowingBack, contentSize: size * 0.82, contentScale: contentScale)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .clipShape(Circle())
                    .zIndex(1)

                if balloon.hasBackSide || hasExplanation {
                    HStack(spacing: 4) {
                        if balloon.hasBackSide {
                            Text(isShowingBack ? "表へ" : "裏あり")
                                .font(.system(size: max(8, 8 * contentScale), weight: .bold))
                                .foregroundStyle(.black.opacity(0.82))
                                .frame(width: max(45, 43 * contentScale), height: max(20, 20 * contentScale))
                                .background(Color.white.opacity(0.92))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.black.opacity(0.14), lineWidth: 1))
                                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
                        }
                        if hasExplanation {
                            explanationButtonView(contentScale: contentScale)
                                .frame(width: 64, height: 30)
                        }
                    }
                        .offset(x: 0, y: -size * 0.38)
                }
            }
            .frame(width: size, height: size)

            Triangle()
                .fill(Color(hex: balloon.colorEndHex))
                .frame(width: size * 0.18, height: size * 0.15)
                .offset(y: -size * 0.03)

            Rectangle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 2, height: size * 0.5)
                .offset(y: -size * 0.03)
        }
        .overlay(alignment: .top) {
            if balloon.itemNumber > 0 {
                Text("\(balloon.itemNumber)")
                    .font(.system(size: max(9, 9 * contentScale), weight: .bold))
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, max(6, 6 * contentScale))
                    .padding(.vertical, max(3, 3 * contentScale))
                    .background(Color.white.opacity(0.92))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
                    .offset(y: size * 0.92)
            }
        }
    }

    @ViewBuilder
    private func contentView(for balloon: BalloonProfile, isShowingBack: Bool, contentSize: Double, contentScale: Double) -> some View {
        let text = isShowingBack ? balloon.backDisplayText : balloon.frontDisplayText
        let imageName = isShowingBack ? balloon.backImageName : balloon.imageName
        let attachedImage = isShowingBack ? balloon.attachedBackImage : balloon.attachedImage
        let imageCaption = isShowingBack ? balloon.backImageCaptionText : balloon.frontImageCaptionText
        let textFontSize = isShowingBack ? balloon.backTextFontSize : balloon.textFontSize
        let imageScale = min(max(isShowingBack ? balloon.backImageScale : balloon.imageScale, 0.6), 2.0)
        let textOffsetX = isShowingBack ? balloon.backTextOffsetX : balloon.textOffsetX
        let textOffsetY = isShowingBack ? balloon.backTextOffsetY : balloon.textOffsetY
        let imageOffsetX = isShowingBack ? balloon.backImageCaptionOffsetX : balloon.imageCaptionOffsetX
        let imageOffsetY = isShowingBack ? balloon.backImageCaptionOffsetY : balloon.imageCaptionOffsetY

        if let image = attachedImage {
            let hasBackBadge = balloon.hasBackSide
            let captionLineCount = imageCaption.map { max(1, $0.components(separatedBy: .newlines).count) } ?? 0
            let captionWidth = contentSize * 0.88
            let captionHeightRatio = captionLineCount > 2 ? 0.32 : (hasBackBadge ? 0.20 : 0.24)
            let captionHeight = contentSize * captionHeightRatio
            let topInsetRatio = hasBackBadge ? 0.16 : 0.02
            let topInset = contentSize * topInsetRatio
            let baseImageHeightRatio = imageCaption == nil ? 0.82 : (captionLineCount > 2 ? 0.48 : (hasBackBadge ? 0.54 : 0.62))
            let imageWidthRatio = 0.82 * imageScale
            let imageHeightRatio = min(1.64, baseImageHeightRatio * imageScale)
            ZStack(alignment: .top) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        maxWidth: contentSize * imageWidthRatio,
                        maxHeight: contentSize * imageHeightRatio
                    )
                    .frame(width: contentSize, height: contentSize, alignment: .center)
                    .offset(x: imageOffsetX * contentSize, y: imageOffsetY * contentSize)
                    .zIndex(1)

                if let imageCaption {
                    Text(imageCaption)
                        .font(.system(size: imageCaptionSize(for: imageCaption, fontSize: textFontSize, contentSize: contentSize, width: captionWidth, height: captionHeight, contentScale: contentScale), weight: .bold))
                        .minimumScaleFactor(0.25)
                        .lineLimit(5)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .frame(width: captionWidth, height: captionHeight, alignment: .center)
                        .offset(x: textOffsetX * contentSize, y: textOffsetY * contentSize)
                        .zIndex(10)
                }
            }
            .padding(.top, topInset)
            .frame(width: contentSize, height: contentSize, alignment: .top)
            .padding(imagePadding(for: contentScale))
        } else if let imageName {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(imagePadding(for: contentScale))
        } else {
            Text(text)
                .font(.system(size: textSize(for: text, fontSize: textFontSize, contentSize: contentSize, contentScale: contentScale), weight: .bold))
                .minimumScaleFactor(0.2)
                .lineLimit(8)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(12 * contentScale)
                .offset(x: textOffsetX * contentSize, y: textOffsetY * contentSize)
        }
    }

    private func imagePadding(for contentScale: Double) -> Double {
        contentScale > 1 ? 0 : 4
    }

    private func imageCaptionSize(for text: String, fontSize: Double, contentSize: Double, width: Double, height: Double, contentScale: Double) -> Double {
        if fontSize > 0 {
            return min(max(fontSize * contentScale * livePreviewScale(for: contentSize), 4), 140 * contentScale)
        }

        let maximumSize = min(24 * contentScale, height * 0.44)
        let minimumSize = max(8, 8 * contentScale)

        var low = minimumSize
        var high = maximumSize
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if text.fitsWithinCaptionArea(width: width, height: height, fontSize: mid) {
                low = mid
            } else {
                high = mid
            }
        }

        return low
    }

    private func textSize(for text: String, fontSize: Double, contentSize: Double, contentScale: Double) -> Double {
        if fontSize > 0 {
            return min(max(fontSize * contentScale * livePreviewScale(for: contentSize), 4), 140 * contentScale)
        }

        let lineCountBudget = max(4, min(8, Int(ceil(Double(text.count) / 7.0))))
        let maximumSize = min(34 * contentScale, contentSize / Double(lineCountBudget) * 0.62)
        let minimumSize = max(14, 12 * contentScale)
        let availableSize = max(contentSize - 24 * contentScale, 20)

        var low = minimumSize
        var high = maximumSize
        for _ in 0..<10 {
            let mid = (low + high) / 2
            if text.fitsWithinBalloonTextArea(width: availableSize, height: availableSize, fontSize: mid) {
                low = mid
            } else {
                high = mid
            }
        }

        return low
    }

    private func livePreviewScale(for contentSize: Double) -> Double {
        max(1, contentSize / 192)
    }
}

private extension String {
    func fitsWithinCaptionArea(width: Double, height: Double, fontSize: Double) -> Bool {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byCharWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .paragraphStyle: paragraphStyle
        ]
        let boundingRect = (self as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return ceil(boundingRect.width) <= width && ceil(boundingRect.height) <= height
    }

    func fitsWithinBalloonTextArea(width: Double, height: Double, fontSize: Double) -> Bool {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byCharWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .paragraphStyle: paragraphStyle
        ]
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingRect = (self as NSString).boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return ceil(boundingRect.width) <= width && ceil(boundingRect.height) <= height
    }
}

private struct ExplanationImageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ExplanationScrollAreaPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct AlwaysVisibleVerticalScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AlwaysVisibleScrollNSView {
        let scrollView = AlwaysVisibleScrollNSView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true

        let documentView = FlippedDocumentView()
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = []
        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        context.coordinator.documentView = documentView
        context.coordinator.hostingView = hostingView
        scrollView.layoutHandler = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.layoutDocument(in: scrollView)
        }
        context.coordinator.layoutDocument(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: AlwaysVisibleScrollNSView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        context.coordinator.layoutDocument(in: scrollView)
        DispatchQueue.main.async {
            context.coordinator.layoutDocument(in: scrollView)
        }
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
        var documentView: FlippedDocumentView?
        private var isLayingOut = false

        func layoutDocument(in scrollView: NSScrollView) {
            guard !isLayingOut,
                  let hostingView,
                  let documentView else { return }

            isLayingOut = true
            defer { isLayingOut = false }

            let previousOrigin = scrollView.contentView.bounds.origin
            let availableWidth = max(1, scrollView.contentSize.width)
            hostingView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: 100_000)
            hostingView.layoutSubtreeIfNeeded()

            let fittingSize = hostingView.fittingSize
            let documentHeight = max(scrollView.contentSize.height, ceil(fittingSize.height))
            let documentSize = NSSize(width: availableWidth, height: documentHeight)
            let maxScrollY = max(0, documentHeight - scrollView.contentSize.height)
            let preservedOrigin = NSPoint(
                x: 0,
                y: min(max(previousOrigin.y, 0), maxScrollY)
            )

            documentView.frame = NSRect(origin: .zero, size: documentSize)
            hostingView.frame = NSRect(origin: .zero, size: documentSize)
            scrollView.contentView.scroll(to: preservedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class AlwaysVisibleScrollNSView: NSScrollView {
    var layoutHandler: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let key = event.specialKey else {
            if event.charactersIgnoringModifiers == " " {
                scrollVertically(by: event.modifierFlags.contains(.shift) ? -contentSize.height * 0.82 : contentSize.height * 0.82)
                return
            }
            super.keyDown(with: event)
            return
        }

        switch key {
        case .upArrow:
            scrollVertically(by: -42)
        case .downArrow:
            scrollVertically(by: 42)
        case .pageUp:
            scrollVertically(by: -contentSize.height * 0.82)
        case .pageDown:
            scrollVertically(by: contentSize.height * 0.82)
        default:
            super.keyDown(with: event)
        }
    }

    private func scrollVertically(by deltaY: CGFloat) {
        guard let documentView else { return }

        let maxY = max(0, documentView.bounds.height - contentSize.height)
        let nextY = min(max(contentView.bounds.origin.y + deltaY, 0), maxY)
        contentView.scroll(to: NSPoint(x: 0, y: nextY))
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        layoutHandler?()
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct ExplanationCloseButtonPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ExplanationZoomOutButtonPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ExplanationZoomInButtonPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct AnswerControlFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AnswerControlFrame: CGRect] = [:]

    static func reduce(value: inout [AnswerControlFrame: CGRect], nextValue: () -> [AnswerControlFrame: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension BalloonProfile {
    var sizeScale: Double {
        OverlaySettings.sizeOptions.first(where: { $0.name == sizeName })?.scale ?? 1.0
    }

    var frontDisplayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "🎈"
    }

    var backDisplayText: String {
        backText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "裏面"
    }

    var frontImageCaptionText: String? {
        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.nilIfEmpty != nil, caption != "🎈" {
            return caption
        }

        return imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var backImageCaptionText: String? {
        backText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var hasBackSide: Bool {
        backText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
    }

    var hasExplanation: Bool {
        explanationText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || !explanationImageDataURLs.isEmpty
    }

    var attachedImage: NSImage? {
        image(from: imageDataURL)
    }

    var attachedBackImage: NSImage? {
        image(from: backImageDataURL)
    }

    var attachedCustomBalloonDesign: NSImage? {
        image(from: customBalloonDesignDataURL)
    }

    var explanationImages: [NSImage] {
        explanationImageDataURLs.compactMap { image(from: $0) }
    }

    var assetImage: NSImage? {
        guard let imageName = imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return NSImage(named: imageName)
    }

    var assetBackImage: NSImage? {
        guard let backImageName = backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return NSImage(named: backImageName)
    }

    private func image(from dataURL: String?) -> NSImage? {
        guard let dataURL,
              let commaIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        return NSImage(data: data)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
