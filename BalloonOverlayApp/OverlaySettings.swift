import Foundation

struct BalloonProfile: Codable, Identifiable {
    let id: UUID
    var itemNumber: Int
    var title: String
    var text: String
    var speechText: String
    var explanationText: String
    var explanationImageDataURLs: [String]
    var imageName: String?
    var imageDataURL: String?
    var backText: String
    var backImageName: String?
    var backImageDataURL: String?
    var textFontSize: Double
    var imageCaptionFontSize: Double
    var imageScale: Double
    var textOffsetX: Double
    var textOffsetY: Double
    var imageCaptionOffsetX: Double
    var imageCaptionOffsetY: Double
    var backTextFontSize: Double
    var backImageScale: Double
    var backTextOffsetX: Double
    var backTextOffsetY: Double
    var backImageCaptionOffsetX: Double
    var backImageCaptionOffsetY: Double
    var genreName: String
    var middleCategoryName: String
    var smallCategoryName: String
    var colorName: String
    var colorStartHex: String
    var colorEndHex: String
    var customBalloonDesignDataURL: String?
    var customBalloonDesignScale: Double
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
        speechText: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        imageScale: Double,
        textOffsetX: Double,
        textOffsetY: Double,
        imageCaptionOffsetX: Double,
        imageCaptionOffsetY: Double,
        backTextFontSize: Double,
        backImageScale: Double,
        backTextOffsetX: Double,
        backTextOffsetY: Double,
        backImageCaptionOffsetX: Double,
        backImageCaptionOffsetY: Double,
        genreName: String,
        middleCategoryName: String,
        smallCategoryName: String,
        colorName: String,
        colorStartHex: String,
        colorEndHex: String,
        customBalloonDesignDataURL: String?,
        customBalloonDesignScale: Double,
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
        self.speechText = speechText
        self.explanationText = explanationText
        self.explanationImageDataURLs = explanationImageDataURLs
        self.imageName = imageName
        self.imageDataURL = imageDataURL
        self.backText = backText
        self.backImageName = backImageName
        self.backImageDataURL = backImageDataURL
        self.textFontSize = textFontSize
        self.imageCaptionFontSize = imageCaptionFontSize
        self.imageScale = imageScale
        self.textOffsetX = textOffsetX
        self.textOffsetY = textOffsetY
        self.imageCaptionOffsetX = imageCaptionOffsetX
        self.imageCaptionOffsetY = imageCaptionOffsetY
        self.backTextFontSize = backTextFontSize
        self.backImageScale = backImageScale
        self.backTextOffsetX = backTextOffsetX
        self.backTextOffsetY = backTextOffsetY
        self.backImageCaptionOffsetX = backImageCaptionOffsetX
        self.backImageCaptionOffsetY = backImageCaptionOffsetY
        self.genreName = genreName
        self.middleCategoryName = middleCategoryName
        self.smallCategoryName = smallCategoryName
        self.colorName = colorName
        self.colorStartHex = colorStartHex
        self.colorEndHex = colorEndHex
        self.customBalloonDesignDataURL = customBalloonDesignDataURL
        self.customBalloonDesignScale = customBalloonDesignScale
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
        speechText = try container.decodeIfPresent(String.self, forKey: .speechText) ?? ""
        explanationText = try container.decodeIfPresent(String.self, forKey: .explanationText) ?? ""
        explanationImageDataURLs = try container.decodeIfPresent([String].self, forKey: .explanationImageDataURLs) ?? []
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        imageDataURL = try container.decodeIfPresent(String.self, forKey: .imageDataURL)
        backText = try container.decodeIfPresent(String.self, forKey: .backText) ?? ""
        backImageName = try container.decodeIfPresent(String.self, forKey: .backImageName)
        backImageDataURL = try container.decodeIfPresent(String.self, forKey: .backImageDataURL)
        textFontSize = try container.decodeIfPresent(Double.self, forKey: .textFontSize) ?? 0
        imageCaptionFontSize = try container.decodeIfPresent(Double.self, forKey: .imageCaptionFontSize) ?? 0
        imageScale = try container.decodeIfPresent(Double.self, forKey: .imageScale) ?? 1.0
        textOffsetX = try container.decodeIfPresent(Double.self, forKey: .textOffsetX) ?? 0
        textOffsetY = try container.decodeIfPresent(Double.self, forKey: .textOffsetY) ?? 0
        imageCaptionOffsetX = try container.decodeIfPresent(Double.self, forKey: .imageCaptionOffsetX) ?? 0
        imageCaptionOffsetY = try container.decodeIfPresent(Double.self, forKey: .imageCaptionOffsetY) ?? 0
        backTextFontSize = try container.decodeIfPresent(Double.self, forKey: .backTextFontSize) ?? textFontSize
        backImageScale = try container.decodeIfPresent(Double.self, forKey: .backImageScale) ?? imageScale
        backTextOffsetX = try container.decodeIfPresent(Double.self, forKey: .backTextOffsetX) ?? textOffsetX
        backTextOffsetY = try container.decodeIfPresent(Double.self, forKey: .backTextOffsetY) ?? textOffsetY
        backImageCaptionOffsetX = try container.decodeIfPresent(Double.self, forKey: .backImageCaptionOffsetX) ?? imageCaptionOffsetX
        backImageCaptionOffsetY = try container.decodeIfPresent(Double.self, forKey: .backImageCaptionOffsetY) ?? imageCaptionOffsetY
        genreName = try container.decodeIfPresent(String.self, forKey: .genreName) ?? "未分類"
        middleCategoryName = try container.decodeIfPresent(String.self, forKey: .middleCategoryName) ?? ""
        smallCategoryName = try container.decodeIfPresent(String.self, forKey: .smallCategoryName) ?? ""
        let decodedColorName = try container.decode(String.self, forKey: .colorName)
        if decodedColorName == "ホワイト" {
            colorName = "濃グレー"
            colorStartHex = "#6b7280"
            colorEndHex = "#374151"
        } else {
            colorName = decodedColorName
            colorStartHex = try container.decode(String.self, forKey: .colorStartHex)
            colorEndHex = try container.decode(String.self, forKey: .colorEndHex)
        }
        customBalloonDesignDataURL = try container.decodeIfPresent(String.self, forKey: .customBalloonDesignDataURL)
        customBalloonDesignScale = try container.decodeIfPresent(Double.self, forKey: .customBalloonDesignScale) ?? 1.0
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
    static let customBalloonDesignName = "自作デザイン"

    static let colorOptions: [BalloonColorOption] = [
        BalloonColorOption(name: "レッド", startHex: "#ff4770", endHex: "#d90d31"),
        BalloonColorOption(name: "ピンク", startHex: "#ff6ec7", endHex: "#d72f91"),
        BalloonColorOption(name: "オレンジ", startHex: "#ff9f43", endHex: "#e86b00"),
        BalloonColorOption(name: "イエロー", startHex: "#ffd84d", endHex: "#f2a900"),
        BalloonColorOption(name: "グリーン", startHex: "#4cd964", endHex: "#159947"),
        BalloonColorOption(name: "ミント", startHex: "#45d6c5", endHex: "#149b90"),
        BalloonColorOption(name: "ブルー", startHex: "#4da3ff", endHex: "#1769e0"),
        BalloonColorOption(name: "パープル", startHex: "#a78bfa", endHex: "#6d45d8"),
        BalloonColorOption(name: "ゴールド", startHex: "#ffd766", endHex: "#b77900"),
        BalloonColorOption(name: "シルバー", startHex: "#f8fafc", endHex: "#94a3b8"),
        BalloonColorOption(name: "濃グレー", startHex: "#6b7280", endHex: "#374151"),
        BalloonColorOption(name: "ブラック", startHex: "#5b6472", endHex: "#171a21")
    ]

    static let positionOptions: [BalloonPositionOption] = [
        BalloonPositionOption(name: "左", ratio: -0.08),
        BalloonPositionOption(name: "中央", ratio: 0.5),
        BalloonPositionOption(name: "右", ratio: 1.08),
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
    var launchPositionName: String
    var isSpeechOutputEnabled: Bool
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

    var hasDisplayableBalloon: Bool {
        temporaryBalloon != nil || hasEnabledBalloons
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
        launchPositionName = defaults.string(forKey: Keys.launchPositionName) ?? "ランダム"
        isSpeechOutputEnabled = defaults.object(forKey: Keys.isSpeechOutputEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.isSpeechOutputEnabled)
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
        if !Self.positionOptions.contains(where: { $0.name == launchPositionName }) {
            launchPositionName = "ランダム"
        }
        migrateLegacyBalloonIfNeeded()
        migrateGenderMiddleCategoriesIfNeeded()
        normalizeGenderedSmallCategoriesIfNeeded()
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

    func setLaunchPositionName(_ positionName: String) {
        updateLaunchSettings(positionName: positionName, climbSpeed: climbSpeed)
    }

    func updateLaunchSettings(positionName: String, climbSpeed: Double, isSpeechOutputEnabled: Bool? = nil) {
        let trimmedPositionName = positionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = Self.positionOptions.first(where: { $0.name == trimmedPositionName }) ?? Self.positionOptions[3]
        launchPositionName = position.name
        self.climbSpeed = min(max(climbSpeed, 40), 900)
        if let isSpeechOutputEnabled {
            self.isSpeechOutputEnabled = isSpeechOutputEnabled
        }
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
            speechText: "",
            explanationText: trimmedDetails,
            explanationImageDataURLs: [],
            imageName: nil,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            imageScale: 1.0,
            textOffsetX: 0,
            textOffsetY: 0,
            imageCaptionOffsetX: 0,
            imageCaptionOffsetY: 0,
            backTextFontSize: 0,
            backImageScale: 1.0,
            backTextOffsetX: 0,
            backTextOffsetY: 0,
            backImageCaptionOffsetX: 0,
            backImageCaptionOffsetY: 0,
            genreName: "Codex通知",
            middleCategoryName: "",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: nil,
            customBalloonDesignScale: 1.0,
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

    func presentTemporaryBalloon(_ balloon: BalloonProfile) {
        temporaryBalloon = balloon
    }

    func addBalloon(
        title: String,
        text: String,
        speechText: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        imageScale: Double,
        textOffsetX: Double,
        textOffsetY: Double,
        imageCaptionOffsetX: Double,
        imageCaptionOffsetY: Double,
        backTextFontSize: Double,
        backImageScale: Double,
        backTextOffsetX: Double,
        backTextOffsetY: Double,
        backImageCaptionOffsetX: Double,
        backImageCaptionOffsetY: Double,
        genreName: String,
        middleCategoryName: String,
        smallCategoryName: String,
        colorName: String,
        customBalloonDesignDataURL: String?,
        customBalloonDesignScale: Double,
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
        let trimmedSpeechText = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationText = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationImageDataURLs = Self.cleanedExplanationImageDataURLs(explanationImageDataURLs)
        let trimmedBackText = backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImageName = imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedImageDataURL = imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedBackImageName = backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedBackImageDataURL = backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmallCategoryName = Self.normalizedSmallCategoryName(smallCategoryName, middleCategoryName: trimmedMiddleCategoryName)
        let trimmedCustomBalloonDesignDataURL = customBalloonDesignDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let resolvedColorName = trimmedCustomBalloonDesignDataURL != nil && colorName == Self.customBalloonDesignName
            ? Self.customBalloonDesignName
            : color.name
        let clampedCustomBalloonDesignScale = Self.clampedCustomBalloonDesignScale(customBalloonDesignScale)
        let clampedTextFontSize = Self.clampedFontSize(textFontSize)
        let clampedImageCaptionFontSize = Self.clampedFontSize(imageCaptionFontSize)
        let clampedImageScale = Self.clampedImageScale(imageScale)
        let clampedTextOffsetX = Self.clampedPositionOffset(textOffsetX)
        let clampedTextOffsetY = Self.clampedPositionOffset(textOffsetY)
        let clampedImageCaptionOffsetX = Self.clampedPositionOffset(imageCaptionOffsetX)
        let clampedImageCaptionOffsetY = Self.clampedPositionOffset(imageCaptionOffsetY)
        let clampedBackTextFontSize = Self.clampedFontSize(backTextFontSize)
        let clampedBackImageScale = Self.clampedImageScale(backImageScale)
        let clampedBackTextOffsetX = Self.clampedPositionOffset(backTextOffsetX)
        let clampedBackTextOffsetY = Self.clampedPositionOffset(backTextOffsetY)
        let clampedBackImageCaptionOffsetX = Self.clampedPositionOffset(backImageCaptionOffsetX)
        let clampedBackImageCaptionOffsetY = Self.clampedPositionOffset(backImageCaptionOffsetY)
        let clampedPauseDuration = min(max(middlePauseDuration, 0.1), 30)

        let balloon = BalloonProfile(
            id: UUID(),
            itemNumber: nextItemNumber(),
            title: trimmedTitle.isEmpty ? "無題の風船" : trimmedTitle,
            text: trimmedText.isEmpty && trimmedImageName == nil && trimmedImageDataURL == nil ? "🎈" : trimmedText,
            speechText: trimmedSpeechText,
            explanationText: trimmedExplanationText,
            explanationImageDataURLs: trimmedExplanationImageDataURLs,
            imageName: trimmedImageName,
            imageDataURL: trimmedImageDataURL,
            backText: trimmedBackText,
            backImageName: trimmedBackImageName,
            backImageDataURL: trimmedBackImageDataURL,
            textFontSize: clampedTextFontSize,
            imageCaptionFontSize: clampedImageCaptionFontSize,
            imageScale: clampedImageScale,
            textOffsetX: clampedTextOffsetX,
            textOffsetY: clampedTextOffsetY,
            imageCaptionOffsetX: clampedImageCaptionOffsetX,
            imageCaptionOffsetY: clampedImageCaptionOffsetY,
            backTextFontSize: clampedBackTextFontSize,
            backImageScale: clampedBackImageScale,
            backTextOffsetX: clampedBackTextOffsetX,
            backTextOffsetY: clampedBackTextOffsetY,
            backImageCaptionOffsetX: clampedBackImageCaptionOffsetX,
            backImageCaptionOffsetY: clampedBackImageCaptionOffsetY,
            genreName: trimmedGenreName.isEmpty ? "未分類" : trimmedGenreName,
            middleCategoryName: trimmedMiddleCategoryName,
            smallCategoryName: trimmedSmallCategoryName,
            colorName: resolvedColorName,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: trimmedCustomBalloonDesignDataURL,
            customBalloonDesignScale: clampedCustomBalloonDesignScale,
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
        speechText: String,
        explanationText: String,
        explanationImageDataURLs: [String],
        imageName: String?,
        imageDataURL: String?,
        backText: String,
        backImageName: String?,
        backImageDataURL: String?,
        textFontSize: Double,
        imageCaptionFontSize: Double,
        imageScale: Double,
        textOffsetX: Double,
        textOffsetY: Double,
        imageCaptionOffsetX: Double,
        imageCaptionOffsetY: Double,
        backTextFontSize: Double,
        backImageScale: Double,
        backTextOffsetX: Double,
        backTextOffsetY: Double,
        backImageCaptionOffsetX: Double,
        backImageCaptionOffsetY: Double,
        genreName: String,
        middleCategoryName: String,
        smallCategoryName: String,
        colorName: String,
        customBalloonDesignDataURL: String?,
        customBalloonDesignScale: Double,
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
        let trimmedSpeechText = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationText = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanationImageDataURLs = Self.cleanedExplanationImageDataURLs(explanationImageDataURLs)
        let trimmedBackText = backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImageName = imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedImageDataURL = imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedBackImageName = backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedBackImageDataURL = backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmallCategoryName = Self.normalizedSmallCategoryName(smallCategoryName, middleCategoryName: trimmedMiddleCategoryName)
        let trimmedCustomBalloonDesignDataURL = customBalloonDesignDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let resolvedColorName = trimmedCustomBalloonDesignDataURL != nil && colorName == Self.customBalloonDesignName
            ? Self.customBalloonDesignName
            : color.name
        let clampedCustomBalloonDesignScale = Self.clampedCustomBalloonDesignScale(customBalloonDesignScale)
        let clampedTextFontSize = Self.clampedFontSize(textFontSize)
        let clampedImageCaptionFontSize = Self.clampedFontSize(imageCaptionFontSize)
        let clampedImageScale = Self.clampedImageScale(imageScale)
        let clampedTextOffsetX = Self.clampedPositionOffset(textOffsetX)
        let clampedTextOffsetY = Self.clampedPositionOffset(textOffsetY)
        let clampedImageCaptionOffsetX = Self.clampedPositionOffset(imageCaptionOffsetX)
        let clampedImageCaptionOffsetY = Self.clampedPositionOffset(imageCaptionOffsetY)
        let clampedBackTextFontSize = Self.clampedFontSize(backTextFontSize)
        let clampedBackImageScale = Self.clampedImageScale(backImageScale)
        let clampedBackTextOffsetX = Self.clampedPositionOffset(backTextOffsetX)
        let clampedBackTextOffsetY = Self.clampedPositionOffset(backTextOffsetY)
        let clampedBackImageCaptionOffsetX = Self.clampedPositionOffset(backImageCaptionOffsetX)
        let clampedBackImageCaptionOffsetY = Self.clampedPositionOffset(backImageCaptionOffsetY)
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
            text: trimmedText.isEmpty && trimmedImageName == nil && trimmedImageDataURL == nil ? "🎈" : trimmedText,
            speechText: trimmedSpeechText,
            explanationText: trimmedExplanationText,
            explanationImageDataURLs: trimmedExplanationImageDataURLs,
            imageName: trimmedImageName,
            imageDataURL: trimmedImageDataURL,
            backText: trimmedBackText,
            backImageName: trimmedBackImageName,
            backImageDataURL: trimmedBackImageDataURL,
            textFontSize: clampedTextFontSize,
            imageCaptionFontSize: clampedImageCaptionFontSize,
            imageScale: clampedImageScale,
            textOffsetX: clampedTextOffsetX,
            textOffsetY: clampedTextOffsetY,
            imageCaptionOffsetX: clampedImageCaptionOffsetX,
            imageCaptionOffsetY: clampedImageCaptionOffsetY,
            backTextFontSize: clampedBackTextFontSize,
            backImageScale: clampedBackImageScale,
            backTextOffsetX: clampedBackTextOffsetX,
            backTextOffsetY: clampedBackTextOffsetY,
            backImageCaptionOffsetX: clampedBackImageCaptionOffsetX,
            backImageCaptionOffsetY: clampedBackImageCaptionOffsetY,
            genreName: trimmedGenreName.isEmpty ? "未分類" : trimmedGenreName,
            middleCategoryName: trimmedMiddleCategoryName,
            smallCategoryName: trimmedSmallCategoryName,
            colorName: resolvedColorName,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: trimmedCustomBalloonDesignDataURL,
            customBalloonDesignScale: clampedCustomBalloonDesignScale,
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
        syncTemporaryBalloonIfNeeded(with: balloons[index])
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
        syncTemporaryBalloonIfNeeded(with: balloons[index])
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
        syncTemporaryBalloonIfNeeded(with: balloons[index])
        activeBalloonID = id
        save()
    }

    func saveAnswerReview(for id: UUID) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }
        balloons[index].lastReviewedAt = Date()
        syncTemporaryBalloonIfNeeded(with: balloons[index])
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
    func presentBalloonOnce(id: UUID) -> Bool {
        guard let balloon = balloons.first(where: { $0.id == id }) else { return false }
        temporaryBalloon = balloon
        return true
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

    func setOnlyBalloonsEnabled(ids enabledIDs: Set<UUID>) {
        guard !balloons.isEmpty else { return }

        allStopSnapshotEnabledIDs.removeAll()
        saveAllStopSnapshot()

        for index in balloons.indices {
            balloons[index].isEnabled = enabledIDs.contains(balloons[index].id)
        }

        activeBalloonID = enabledBalloons.last?.id
        save()
    }

    func setBalloonsEnabled(ids targetIDs: Set<UUID>, isEnabled: Bool) {
        guard !targetIDs.isEmpty else { return }
        var changedIDs: [UUID] = []

        for index in balloons.indices {
            guard targetIDs.contains(balloons[index].id) else { continue }

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

    func setBalloonsEnabled(inGenre genreName: String, middleCategoryName: String, isEnabled: Bool) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        var changedIDs: [UUID] = []

        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            guard balloonGenreName == targetGenreName, balloonMiddleCategoryName == targetMiddleCategoryName else { continue }

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

    func setBalloonsEnabled(inGenre genreName: String, middleCategoryName: String, smallCategoryName: String, isEnabled: Bool) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        let targetSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        var changedIDs: [UUID] = []

        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let balloonSmallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            guard balloonGenreName == targetGenreName,
                  balloonMiddleCategoryName == targetMiddleCategoryName,
                  balloonSmallCategoryName == targetSmallCategoryName else { continue }

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
            balloons[index].middleCategoryName = ""
            balloons[index].smallCategoryName = ""
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func renameMiddleCategory(inGenre genreName: String, from oldName: String, to newName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetMiddleCategoryName.isEmpty, !replacementName.isEmpty, targetMiddleCategoryName != replacementName else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName, balloonMiddleCategoryName == targetMiddleCategoryName else { continue }

            balloons[index].middleCategoryName = replacementName
            balloons[index].smallCategoryName = Self.normalizedSmallCategoryName(
                balloons[index].smallCategoryName,
                middleCategoryName: replacementName
            )
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func deleteMiddleCategory(inGenre genreName: String, named middleCategoryName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetMiddleCategoryName.isEmpty else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName, balloonMiddleCategoryName == targetMiddleCategoryName else { continue }

            balloons[index].middleCategoryName = ""
            balloons[index].smallCategoryName = ""
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func renameSmallCategory(inGenre genreName: String, middleCategoryName: String, from oldName: String, to newName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        let targetSmallCategoryName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementName = Self.normalizedSmallCategoryName(newName, middleCategoryName: targetMiddleCategoryName)
        guard !targetSmallCategoryName.isEmpty, !replacementName.isEmpty, targetSmallCategoryName != replacementName else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let balloonSmallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName,
                  balloonMiddleCategoryName == targetMiddleCategoryName,
                  balloonSmallCategoryName == targetSmallCategoryName else { continue }

            balloons[index].smallCategoryName = replacementName
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func deleteSmallCategory(inGenre genreName: String, middleCategoryName: String, named smallCategoryName: String) {
        let targetGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let targetMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        let targetSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetSmallCategoryName.isEmpty else { return }

        var didChange = false
        for index in balloons.indices {
            let balloonGenreName = balloons[index].genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let balloonMiddleCategoryName = balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let balloonSmallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard balloonGenreName == targetGenreName,
                  balloonMiddleCategoryName == targetMiddleCategoryName,
                  balloonSmallCategoryName == targetSmallCategoryName else { continue }

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
        defaults.set(launchPositionName, forKey: Keys.launchPositionName)
        defaults.set(isSpeechOutputEnabled, forKey: Keys.isSpeechOutputEnabled)
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
                .prefix(8)
        )
    }

    private func saveAllStopSnapshot() {
        defaults.set(allStopSnapshotEnabledIDs.map(\.uuidString), forKey: Keys.allStopSnapshotEnabledIDs)
    }

    private func syncTemporaryBalloonIfNeeded(with balloon: BalloonProfile) {
        guard temporaryBalloon?.id == balloon.id else { return }
        temporaryBalloon = balloon
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
            speechText: "",
            explanationText: "",
            explanationImageDataURLs: [],
            imageName: imageName?.nilIfEmpty,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            imageScale: 1.0,
            textOffsetX: 0,
            textOffsetY: 0,
            imageCaptionOffsetX: 0,
            imageCaptionOffsetY: 0,
            backTextFontSize: 0,
            backImageScale: 1.0,
            backTextOffsetX: 0,
            backTextOffsetY: 0,
            backImageCaptionOffsetX: 0,
            backImageCaptionOffsetY: 0,
            genreName: "未分類",
            middleCategoryName: "",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: nil,
            customBalloonDesignScale: 1.0,
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

    private func migrateGenderMiddleCategoriesIfNeeded() {
        guard !defaults.bool(forKey: Keys.didMigrateGenderMiddleCategories) else { return }

        var didChange = false

        for index in balloons.indices {
            guard balloons[index].middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let smallCategoryName = balloons[index].smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            if smallCategoryName.contains("レディース") {
                balloons[index].middleCategoryName = "レディース"
                didChange = true
            } else if smallCategoryName.contains("メンズ") {
                balloons[index].middleCategoryName = "メンズ"
                didChange = true
            }
        }

        if didChange {
            save()
        }
        defaults.set(true, forKey: Keys.didMigrateGenderMiddleCategories)
    }

    private func normalizeGenderedSmallCategoriesIfNeeded() {
        var didChange = false

        for index in balloons.indices {
            let normalizedName = Self.normalizedSmallCategoryName(
                balloons[index].smallCategoryName,
                middleCategoryName: balloons[index].middleCategoryName
            )
            guard normalizedName != balloons[index].smallCategoryName else { continue }

            balloons[index].smallCategoryName = normalizedName
            didChange = true
        }

        if didChange {
            save()
        }
    }

    private static func defaultBalloon() -> BalloonProfile {
        let color = colorOptions[0]
        return BalloonProfile(
            id: UUID(),
            itemNumber: 0,
            title: "風船",
            text: "🎈",
            speechText: "",
            explanationText: "",
            explanationImageDataURLs: [],
            imageName: nil,
            imageDataURL: nil,
            backText: "",
            backImageName: nil,
            backImageDataURL: nil,
            textFontSize: 0,
            imageCaptionFontSize: 0,
            imageScale: 1.0,
            textOffsetX: 0,
            textOffsetY: 0,
            imageCaptionOffsetX: 0,
            imageCaptionOffsetY: 0,
            backTextFontSize: 0,
            backImageScale: 1.0,
            backTextOffsetX: 0,
            backTextOffsetY: 0,
            backImageCaptionOffsetX: 0,
            backImageCaptionOffsetY: 0,
            genreName: "未分類",
            middleCategoryName: "",
            smallCategoryName: "",
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: nil,
            customBalloonDesignScale: 1.0,
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
        return min(max(value, 4), 90)
    }

    private static func clampedCustomBalloonDesignScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, 0.5), 2.5)
    }

    private static func clampedImageScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, 0.6), 2.0)
    }

    private static func clampedPositionOffset(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -0.45), 0.45)
    }

    private static func normalizedSmallCategoryName(_ smallCategoryName: String, middleCategoryName: String) -> String {
        let trimmedName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMiddleCategoryName = middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMiddleCategoryName == "メンズ" || trimmedMiddleCategoryName == "レディース" else {
            return trimmedName
        }

        let normalizedName = trimmedName
            .replacingOccurrences(of: trimmedMiddleCategoryName, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName.isEmpty ? trimmedName : normalizedName
    }
}

private enum Keys {
    static let displayInterval = "displayInterval"
    static let randomIntervalMinSeconds = "randomIntervalMinSeconds"
    static let randomIntervalMaxSeconds = "randomIntervalMaxSeconds"
    static let climbSpeed = "climbSpeed"
    static let launchPositionName = "launchPositionName"
    static let isSpeechOutputEnabled = "isSpeechOutputEnabled"
    static let balloons = "balloons"
    static let activeBalloonID = "activeBalloonID"
    static let isPaused = "isPaused"
    static let allStopSnapshotEnabledIDs = "allStopSnapshotEnabledIDs"
    static let didMigrateGenderMiddleCategories = "didMigrateGenderMiddleCategories"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
