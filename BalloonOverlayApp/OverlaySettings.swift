import Foundation

struct BalloonProfile: Codable, Identifiable {
    let id: UUID
    var itemNumber: Int
    var title: String
    var text: String
    var explanationText: String
    var explanationImageDataURLs: [String]
    var imageName: String?
    var imageDataURL: String?
    var backText: String
    var backImageName: String?
    var backImageDataURL: String?
    var textFontSize: Double
    var imageCaptionFontSize: Double
    var genreName: String
    var smallCategoryName: String
    var colorName: String
    var colorStartHex: String
    var colorEndHex: String
    var positionName: String
    var sizeName: String
    var pausesAtMiddle: Bool
    var middlePauseDuration: Double
    var isEnabled: Bool
    var isFavorite: Bool
    var correctCount: Int
    var incorrectCount: Int
    var lastReviewedAt: Date?
    var createdAt: Date

    init(
        id: UUID,
        itemNumber: Int,
        title: String,
        text: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        genreName: String,
        smallCategoryName: String,
        colorName: String,
        colorStartHex: String,
        colorEndHex: String,
        positionName: String,
        sizeName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double,
        isEnabled: Bool,
        isFavorite: Bool,
        correctCount: Int,
        incorrectCount: Int,
        lastReviewedAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.itemNumber = itemNumber
        self.title = title
        self.text = text
        self.explanationText = explanationText
        self.explanationImageDataURLs = explanationImageDataURLs
        self.imageName = imageName
        self.imageDataURL = imageDataURL
        self.backText = backText
        self.backImageName = backImageName
        self.backImageDataURL = backImageDataURL
        self.textFontSize = textFontSize
        self.imageCaptionFontSize = imageCaptionFontSize
        self.genreName = genreName
        self.smallCategoryName = smallCategoryName
        self.colorName = colorName
        self.colorStartHex = colorStartHex
        self.colorEndHex = colorEndHex
        self.positionName = positionName
        self.sizeName = sizeName
        self.pausesAtMiddle = pausesAtMiddle
        self.middlePauseDuration = middlePauseDuration
        self.isEnabled = isEnabled
        self.isFavorite = isFavorite
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.lastReviewedAt = lastReviewedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        itemNumber = try container.decodeIfPresent(Int.self, forKey: .itemNumber) ?? 0
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        explanationText = try container.decodeIfPresent(String.self, forKey: .explanationText) ?? ""
        explanationImageDataURLs = try container.decodeIfPresent([String].self, forKey: .explanationImageDataURLs) ?? []
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        imageDataURL = try container.decodeIfPresent(String.self, forKey: .imageDataURL)
        backText = try container.decodeIfPresent(String.self, forKey: .backText) ?? ""
        backImageName = try container.decodeIfPresent(String.self, forKey: .backImageName)
        backImageDataURL = try container.decodeIfPresent(String.self, forKey: .backImageDataURL)
        textFontSize = try container.decodeIfPresent(Double.self, forKey: .textFontSize) ?? 0
        imageCaptionFontSize = try container.decodeIfPresent(Double.self, forKey: .imageCaptionFontSize) ?? 0
        genreName = try container.decodeIfPresent(String.self, forKey: .genreName) ?? "未分類"
        smallCategoryName = try container.decodeIfPresent(String.self, forKey: .smallCategoryName) ?? ""
        colorName = try container.decode(String.self, forKey: .colorName)
        colorStartHex = try container.decode(String.self, forKey: .colorStartHex)
        colorEndHex = try container.decode(String.self, forKey: .colorEndHex)
        positionName = try container.decodeIfPresent(String.self, forKey: .positionName) ?? "中央"
        sizeName = try container.decodeIfPresent(String.self, forKey: .sizeName) ?? "標準"
        pausesAtMiddle = try container.decodeIfPresent(Bool.self, forKey: .pausesAtMiddle) ?? false
        middlePauseDuration = try container.decodeIfPresent(Double.self, forKey: .middlePauseDuration) ?? 1.0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        correctCount = try container.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        incorrectCount = try container.decodeIfPresent(Int.self, forKey: .incorrectCount) ?? 0
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct BalloonColorOption {
    let name: String
    let startHex: String
    let endHex: String
}

struct BalloonPositionOption {
    let name: String
    let ratio: Double?
}

struct BalloonSizeOption {
    let name: String
    let scale: Double
}

final class OverlaySettings {
    static let colorOptions: [BalloonColorOption] = [
        BalloonColorOption(name: "レッド", startHex: "#ff4770", endHex: "#d90d31"),
        BalloonColorOption(name: "ピンク", startHex: "#ff6ec7", endHex: "#d72f91"),
        BalloonColorOption(name: "オレンジ", startHex: "#ff9f43", endHex: "#e86b00"),
        BalloonColorOption(name: "イエロー", startHex: "#ffd84d", endHex: "#f2a900"),
        BalloonColorOption(name: "グリーン", startHex: "#4cd964", endHex: "#159947"),
        BalloonColorOption(name: "ミント", startHex: "#45d6c5", endHex: "#149b90"),
        BalloonColorOption(name: "ブルー", startHex: "#4da3ff", endHex: "#1769e0"),
        BalloonColorOption(name: "パープル", startHex: "#a78bfa", endHex: "#6d45d8"),
        BalloonColorOption(name: "ホワイト", startHex: "#ffffff", endHex: "#dfe4ea"),
        BalloonColorOption(name: "ブラック", startHex: "#5b6472", endHex: "#171a21")
    ]

    static let positionOptions: [BalloonPositionOption] = [
        BalloonPositionOption(name: "左", ratio: 0.2),
        BalloonPositionOption(name: "中央", ratio: 0.5),
        BalloonPositionOption(name: "右", ratio: 0.8),
        BalloonPositionOption(name: "ランダム", ratio: nil)
    ]

    static let sizeOptions: [BalloonSizeOption] = [
        BalloonSizeOption(name: "標準", scale: 1.0),
        BalloonSizeOption(name: "ラージ", scale: 2.0),
        BalloonSizeOption(name: "特大", scale: 3.0)
    ]

    private let defaults: UserDefaults

    var displayInterval: TimeInterval
    var randomIntervalMinSeconds: TimeInterval
    var randomIntervalMaxSeconds: TimeInterval
    var climbSpeed: Double
    var balloons: [BalloonProfile]
    var activeBalloonID: UUID?
    var isPaused: Bool
    private var temporaryBalloon: BalloonProfile?
    private var allStopSnapshotEnabledIDs: Set<UUID>

    var enabledBalloons: [BalloonProfile] {
        balloons.filter(\.isEnabled)
    }

    var hasEnabledBalloons: Bool {
        !enabledBalloons.isEmpty
    }

    var canRestoreAllStopState: Bool {
        !allStopSnapshotEnabledIDs.isEmpty
    }

    var activeBalloon: BalloonProfile {
        if let temporaryBalloon {
            return temporaryBalloon
        }

        if let activeBalloonID, let balloon = balloons.first(where: { $0.id == activeBalloonID && $0.isEnabled }) {
            return balloon
        }

        if let balloon = enabledBalloons.last {
            return balloon
        }

        return Self.defaultBalloon()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayInterval = defaults.double(forKey: Keys.displayInterval)
        randomIntervalMinSeconds = defaults.double(forKey: Keys.randomIntervalMinSeconds)
        randomIntervalMaxSeconds = defaults.double(forKey: Keys.randomIntervalMaxSeconds)
        climbSpeed = defaults.double(forKey: Keys.climbSpeed)
        activeBalloonID = defaults.string(forKey: Keys.activeBalloonID).flatMap(UUID.init(uuidString:))
        isPaused = defaults.bool(forKey: Keys.isPaused)
        allStopSnapshotEnabledIDs = Set(
            defaults.stringArray(forKey: Keys.allStopSnapshotEnabledIDs)?
                .compactMap(UUID.init(uuidString:)) ?? []
        )

        if let data = defaults.data(forKey: Keys.balloons),
           let decoded = try? JSONDecoder().decode([BalloonProfile].self, from: data) {
            balloons = decoded
        } else {
            balloons = []
        }

        if displayInterval <= 0 {
            displayInterval = 30 * 60
        }
        if randomIntervalMinSeconds <= 0 {
            randomIntervalMinSeconds = 5
        }
        if randomIntervalMaxSeconds < randomIntervalMinSeconds {
            randomIntervalMaxSeconds = max(randomIntervalMinSeconds, 600)
        }
        if defaults.object(forKey: Keys.climbSpeed) == nil || climbSpeed <= 0 || climbSpeed == 300 || climbSpeed == 350 {
            climbSpeed = 400
        }
        migrateLegacyBalloonIfNeeded()
        assignMissingItemNumbersIfNeeded()
    }

    func updateGlobalSettings(
        intervalMinutes: Double,
        randomIntervalMinSeconds: Double,
        randomIntervalMaxSeconds: Double,
        climbSpeed: Double
    ) {
        displayInterval = max(intervalMinutes, 0.1) * 60
        let minSeconds = max(randomIntervalMinSeconds, 1)
        let maxSeconds = max(randomIntervalMaxSeconds, minSeconds)
        self.randomIntervalMinSeconds = minSeconds
        self.randomIntervalMaxSeconds = maxSeconds
        self.climbSpeed = min(max(climbSpeed, 40), 900)
        save()
    }

    func nextDisplayInterval() -> TimeInterval {
        let enabledCount = max(enabledBalloons.count, 1)
        let minSeconds = max(randomIntervalMinSeconds, 1)
        let maxSecondsForOneCycle = max(randomIntervalMaxSeconds, minSeconds)
        let maxSecondsPerBalloon = max(minSeconds, maxSecondsForOneCycle / Double(enabledCount))

        return TimeInterval.random(in: minSeconds...maxSecondsPerBalloon)
    }

    func presentCodexCompletionBalloon(title: String, message: String, details: String, isSuccess: Bool) {
        let color = isSuccess
            ? BalloonColorOption(name: "グリーン", startHex: "#4cd964", endHex: "#159947")
            : BalloonColorOption(name: "オレンジ", startHex: "#ff9f43", endHex: "#e86b00")
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Codex作業完了"
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (isSuccess ? "作業が完了しました" : "作業で確認が必要です")
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        temporaryBalloon = BalloonProfile(
            id: UUID(),
            itemNumber: 0,
            title: trimmedTitle,
            text: trimmedMessage,
            explanationText: trimmedDetails,
            explanationImageDataURLs: [],
            imageName: nil,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            genreName: "Codex通知",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: "中央",
            sizeName: "ラージ",
            pausesAtMiddle: true,
            middlePauseDuration: 300,
            isEnabled: true,
            isFavorite: false,
            correctCount: 0,
            incorrectCount: 0,
            lastReviewedAt: nil,
            createdAt: Date()
        )
    }

    func clearTemporaryBalloon() {
        temporaryBalloon = nil
    }

    func addBalloon(
        title: String,
        text: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        genreName: String,
        smallCategoryName: String,
        colorName: String,
        positionName: String,
        sizeName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double
    ) {
        let color = Self.colorOptions.first(where: { $0.name == colorName }) ?? Self.colorOptions[0]
        let position = Self.positionOptions.first(where: { $0.name == positionName }) ?? Self.positionOptions[1]
        let size = Self.sizeOptions.first(where: { $0.name == sizeName }) ?? Self.sizeOptions[0]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationText = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationImageDataURLs = Self.cleanedExplanationImageDataURLs(explanationImageDataURLs)
        let trimmedBackText = backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedTextFontSize = Self.clampedFontSize(textFontSize)
        let clampedImageCaptionFontSize = Self.clampedFontSize(imageCaptionFontSize)
        let clampedPauseDuration = min(max(middlePauseDuration, 0.1), 30)

        let balloon = BalloonProfile(
            id: UUID(),
            itemNumber: nextItemNumber(),
            title: trimmedTitle.isEmpty ? "無題の風船" : trimmedTitle,
            text: trimmedText.isEmpty ? "🎈" : trimmedText,
            explanationText: trimmedExplanationText,
            explanationImageDataURLs: trimmedExplanationImageDataURLs,
            imageName: imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            imageDataURL: imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            backText: trimmedBackText,
            backImageName: backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            backImageDataURL: backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            textFontSize: clampedTextFontSize,
            imageCaptionFontSize: clampedImageCaptionFontSize,
            genreName: trimmedGenreName.isEmpty ? "未分類" : trimmedGenreName,
            smallCategoryName: trimmedSmallCategoryName,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: position.name,
            sizeName: size.name,
            pausesAtMiddle: pausesAtMiddle,
            middlePauseDuration: clampedPauseDuration,
            isEnabled: true,
            isFavorite: false,
            correctCount: 0,
            incorrectCount: 0,
            lastReviewedAt: nil,
            createdAt: Date()
        )

        balloons.append(balloon)
        activeBalloonID = balloon.id
        save()
    }

    func updateBalloon(
        id: UUID,
        title: String,
        text: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        genreName: String,
        smallCategoryName: String,
        colorName: String,
        positionName: String,
        sizeName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double
    ) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }

        let color = Self.colorOptions.first(where: { $0.name == colorName }) ?? Self.colorOptions[0]
        let position = Self.positionOptions.first(where: { $0.name == positionName }) ?? Self.positionOptions[1]
        let size = Self.sizeOptions.first(where: { $0.name == sizeName }) ?? Self.sizeOptions[0]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationText = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationImageDataURLs = Self.cleanedExplanationImageDataURLs(explanationImageDataURLs)
        let trimmedBackText = backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedTextFontSize = Self.clampedFontSize(textFontSize)
        let clampedImageCaptionFontSize = Self.clampedFontSize(imageCaptionFontSize)
        let clampedPauseDuration = min(max(middlePauseDuration, 0.1), 30)
        let createdAt = balloons[index].createdAt
        let isEnabled = balloons[index].isEnabled
        let isFavorite = balloons[index].isFavorite
        let correctCount = balloons[index].correctCount
        let incorrectCount = balloons[index].incorrectCount
        let itemNumber = balloons[index].itemNumber
        let lastReviewedAt = balloons[index].lastReviewedAt

        balloons[index] = BalloonProfile(
            id: id,
            itemNumber: itemNumber,
            title: trimmedTitle.isEmpty ? "無題の風船" : trimmedTitle,
            text: trimmedText.isEmpty ? "🎈" : trimmedText,
            explanationText: trimmedExplanationText,
            explanationImageDataURLs: trimmedExplanationImageDataURLs,
            imageName: imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            imageDataURL: imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            backText: trimmedBackText,
            backImageName: backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            backImageDataURL: backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            textFontSize: clampedTextFontSize,
            imageCaptionFontSize: clampedImageCaptionFontSize,
            genreName: trimmedGenreName.isEmpty ? "未分類" : trimmedGenreName,
            smallCategoryName: trimmedSmallCategoryName,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: position.name,
            sizeName: size.name,
            pausesAtMiddle: pausesAtMiddle,
            middlePauseDuration: clampedPauseDuration,
            isEnabled: isEnabled,
            isFavorite: isFavorite,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            lastReviewedAt: lastReviewedAt,
            createdAt: createdAt
        )
        activeBalloonID = id
        save()
    }

    func recordAnswer(for id: UUID, isCorrect: Bool) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        if isCorrect {
            balloons[index].correctCount += 1
        } else {
            balloons[index].incorrectCount += 1
        }
        activeBalloonID = id
        save()
    }

    func undoAnswer(for id: UUID, isCorrect: Bool) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        if isCorrect {
            balloons[index].correctCount = max(0, balloons[index].correctCount - 1)
        } else {
            balloons[index].incorrectCount = max(0, balloons[index].incorrectCount - 1)
        }
        activeBalloonID = id
        save()
    }

    func adjustAnswerCount(for id: UUID, isCorrect: Bool, delta: Int) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        if isCorrect {
            balloons[index].correctCount = max(0, balloons[index].correctCount + delta)
        } else {
            balloons[index].incorrectCount = max(0, balloons[index].incorrectCount + delta)
        }
        activeBalloonID = id
        save()
    }

    func saveAnswerReview(for id: UUID) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        balloons[index].lastReviewedAt = Date()
        activeBalloonID = id
        save()
    }

    func activateBalloon(id: UUID) {
        temporaryBalloon = nil
        guard balloons.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        activeBalloonID = id
        save()
    }

    @discardableResult
    func activateNextEnabledBalloon() -> Bool {
        temporaryBalloon = nil
        let enabledIDs = balloons.filter(\.isEnabled).map(\.id)
        guard !enabledIDs.isEmpty else { return false }

        if let activeBalloonID,
           let currentIndex = enabledIDs.firstIndex(of: activeBalloonID) {
            let nextIndex = enabledIDs.index(after: currentIndex)
            self.activeBalloonID = nextIndex == enabledIDs.endIndex ? enabledIDs[0] : enabledIDs[nextIndex]
        } else {
            activeBalloonID = enabledIDs[0]
        }

        save()
        return true
    }

    func setBalloonEnabled(id: UUID, isEnabled: Bool) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        balloons[index].isEnabled = isEnabled

        if isEnabled {
            activeBalloonID = id
        } else if activeBalloonID == id {
            activeBalloonID = enabledBalloons.last?.id
        }

        save()
    }

    func setBalloonFavorite(id: UUID, isFavorite: Bool) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        balloons[index].isFavorite = isFavorite
        save()
    }

    func setAllBalloonsEnabled(_ isEnabled: Bool) {
        guard !balloons.isEmpty else { return }

        if !isEnabled {
            allStopSnapshotEnabledIDs = Set(enabledBalloons.map(\.id))
            saveAllStopSnapshot()
        } else {
            allStopSnapshotEnabledIDs.removeAll()
            saveAllStopSnapshot()
        }

        for index in balloons.indices {
            balloons[index].isEnabled = isEnabled
        }

        activeBalloonID = isEnabled ? balloons.last?.id : nil
        save()
    }

    func setBalloonsEnabled(inGenre genreName: String, isEnabled: Bool) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        var changedIDs: [UUID] = []

        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            guard balloonGenreName == targetGenreName else { continue }

            balloons[index].isEnabled = isEnabled
            changedIDs.append(balloons[index].id)
        }

        guard !changedIDs.isEmpty else { return }

        if isEnabled {
            activeBalloonID = changedIDs.last
        } else if let activeBalloonID, changedIDs.contains(activeBalloonID) {
            self.activeBalloonID = enabledBalloons.last?.id
        }

        save()
    }

    func renameGenre(from oldName: String, to newName: String) {
        let targetName = oldName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let replacementName = newName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        guard targetName != replacementName else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            guard balloonGenreName == targetName else { continue }

            balloons[index].genreName = replacementName
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func deleteGenre(named genreName: String) {
        let targetName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        guard targetName != "未分類" else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            guard balloonGenreName == targetName else { continue }

            balloons[index].genreName = "未分類"
            balloons[index].smallCategoryName = ""
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func renameSmallCategory(inGenre genreName: String, from oldName: String, to newName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetSmallCategoryName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetSmallCategoryName.isEmpty, !replacementName.isEmpty, targetSmallCategoryName != replacementName else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonSmallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName, balloonSmallCategoryName == targetSmallCategoryName else { continue }

            balloons[index].smallCategoryName = replacementName
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func deleteSmallCategory(inGenre genreName: String, named smallCategoryName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetSmallCategoryName.isEmpty else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonSmallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName, balloonSmallCategoryName == targetSmallCategoryName else { continue }

            balloons[index].smallCategoryName = ""
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func restoreAllStopState() {
        guard !allStopSnapshotEnabledIDs.isEmpty else { return }

        for index in balloons.indices {
            balloons[index].isEnabled = allStopSnapshotEnabledIDs.contains(balloons[index].id)
        }

        activeBalloonID = enabledBalloons.last?.id
        allStopSnapshotEnabledIDs.removeAll()
        saveAllStopSnapshot()
        save()
    }

    func deleteBalloon(id: UUID) {
        balloons.removeAll { $0.id == id }
        if activeBalloonID == id {
            activeBalloonID = enabledBalloons.last?.id
        }
        save()
    }

    func setPaused(_ isPaused: Bool) {
        self.isPaused = isPaused
        defaults.set(isPaused, forKey: Keys.isPaused)
    }

    private func save() {
        defaults.set(displayInterval, forKey: Keys.displayInterval)
        defaults.set(randomIntervalMinSeconds, forKey: Keys.randomIntervalMinSeconds)
        defaults.set(randomIntervalMaxSeconds, forKey: Keys.randomIntervalMaxSeconds)
        defaults.set(climbSpeed, forKey: Keys.climbSpeed)
        defaults.set(activeBalloonID?.uuidString, forKey: Keys.activeBalloonID)

        if let encoded = try? JSONEncoder().encode(balloons) {
            defaults.set(encoded, forKey: Keys.balloons)
        }
    }

    private static func cleanedExplanationImageDataURLs(_ dataURLs: [String]) -> [String] {
        Array(
            dataURLs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(4)
        )
    }

    private func saveAllStopSnapshot() {
        defaults.set(allStopSnapshotEnabledIDs.map(\.uuidString), forKey: Keys.allStopSnapshotEnabledIDs)
    }

    private func nextItemNumber() -> Int {
        (balloons.map(\.itemNumber).max() ?? 0) + 1
    }

    private func assignMissingItemNumbersIfNeeded() {
        var usedNumbers: Set<Int> = []
        var nextNumber = (balloons.map(\.itemNumber).filter { $0 > 0 }.max() ?? 0) + 1
        var didChange = false

        for index in balloons.indices {
            let currentNumber = balloons[index].itemNumber
            if currentNumber > 0, !usedNumbers.contains(currentNumber) {
                usedNumbers.insert(currentNumber)
                continue
            }

            while usedNumbers.contains(nextNumber) {
                nextNumber += 1
            }
            balloons[index].itemNumber = nextNumber
            usedNumbers.insert(nextNumber)
            nextNumber += 1
            didChange = true
        }

        if didChange {
            save()
        }
    }

    private func migrateLegacyBalloonIfNeeded() {
        guard balloons.isEmpty else { return }

        let text = defaults.string(forKey: "balloonText")
            ?? defaults.string(forKey: "balloonEmoji")
            ?? "🎈"
        let imageName = defaults.string(forKey: "imageName")
        let color = Self.colorOptions[0]

        let balloon = BalloonProfile(
            id: UUID(),
            itemNumber: nextItemNumber(),
            title: "最初の風船",
            text: text,
            explanationText: "",
            explanationImageDataURLs: [],
            imageName: imageName?.nilIfEmpty,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            genreName: "未分類",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: "ランダム",
            sizeName: "標準",
            pausesAtMiddle: false,
            middlePauseDuration: 15.0,
            isEnabled: true,
            isFavorite: false,
            correctCount: 0,
            incorrectCount: 0,
            lastReviewedAt: nil,
            createdAt: Date()
        )
        balloons = [balloon]
        activeBalloonID = balloon.id
        save()
    }

    private static func defaultBalloon() -> BalloonProfile {
        let color = colorOptions[0]
        return BalloonProfile(
            id: UUID(),
            itemNumber: 0,
            title: "風船",
            text: "🎈",
            explanationText: "",
            explanationImageDataURLs: [],
            imageName: nil,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            genreName: "未分類",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: "ランダム",
            sizeName: "標準",
            pausesAtMiddle: false,
            middlePauseDuration: 15.0,
            isEnabled: true,
            isFavorite: false,
            correctCount: 0,
            incorrectCount: 0,
            lastReviewedAt: nil,
            createdAt: Date()
        )
    }

    private static func clampedFontSize(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(max(value, 8), 90)
    }
}

private enum Keys {
    static let displayInterval = "displayInterval"
    static let randomIntervalMinSeconds = "randomIntervalMinSeconds"
    static let randomIntervalMaxSeconds = "randomIntervalMaxSeconds"
    static let climbSpeed = "climbSpeed"
    static let balloons = "balloons"
    static let activeBalloonID = "activeBalloonID"
    static let isPaused = "isPaused"
    static let allStopSnapshotEnabledIDs = "allStopSnapshotEnabledIDs"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
