import Foundation

struct BalloonProfile: Codable, Identifiable {
    let id: UUID
    var title: String
    var text: String
    var imageName: String?
    var colorName: String
    var colorStartHex: String
    var colorEndHex: String
    var positionName: String
    var pausesAtMiddle: Bool
    var middlePauseDuration: Double
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID,
        title: String,
        text: String,
        imageName: String?,
        colorName: String,
        colorStartHex: String,
        colorEndHex: String,
        positionName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.imageName = imageName
        self.colorName = colorName
        self.colorStartHex = colorStartHex
        self.colorEndHex = colorEndHex
        self.positionName = positionName
        self.pausesAtMiddle = pausesAtMiddle
        self.middlePauseDuration = middlePauseDuration
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        colorName = try container.decode(String.self, forKey: .colorName)
        colorStartHex = try container.decode(String.self, forKey: .colorStartHex)
        colorEndHex = try container.decode(String.self, forKey: .colorEndHex)
        positionName = try container.decodeIfPresent(String.self, forKey: .positionName) ?? "中央"
        pausesAtMiddle = try container.decodeIfPresent(Bool.self, forKey: .pausesAtMiddle) ?? false
        middlePauseDuration = try container.decodeIfPresent(Double.self, forKey: .middlePauseDuration) ?? 1.0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
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

    private let defaults: UserDefaults

    var displayInterval: TimeInterval
    var climbSpeed: Double
    var balloons: [BalloonProfile]
    var activeBalloonID: UUID?
    var isPaused: Bool

    var enabledBalloons: [BalloonProfile] {
        balloons.filter(\.isEnabled)
    }

    var hasEnabledBalloons: Bool {
        !enabledBalloons.isEmpty
    }

    var activeBalloon: BalloonProfile {
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
        climbSpeed = defaults.double(forKey: Keys.climbSpeed)
        activeBalloonID = defaults.string(forKey: Keys.activeBalloonID).flatMap(UUID.init(uuidString:))
        isPaused = defaults.bool(forKey: Keys.isPaused)

        if let data = defaults.data(forKey: Keys.balloons),
           let decoded = try? JSONDecoder().decode([BalloonProfile].self, from: data) {
            balloons = decoded
        } else {
            balloons = []
        }

        if displayInterval <= 0 {
            displayInterval = 30 * 60
        }
        if climbSpeed <= 0 {
            climbSpeed = 180
        }
        migrateLegacyBalloonIfNeeded()
    }

    func updateGlobalSettings(intervalMinutes: Double, climbSpeed: Double) {
        displayInterval = max(intervalMinutes, 0.1) * 60
        self.climbSpeed = min(max(climbSpeed, 40), 900)
        save()
    }

    func addBalloon(
        title: String,
        text: String,
        imageName: String?,
        colorName: String,
        positionName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double
    ) {
        let color = Self.colorOptions.first(where: { $0.name == colorName }) ?? Self.colorOptions[0]
        let position = Self.positionOptions.first(where: { $0.name == positionName }) ?? Self.positionOptions[1]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPauseDuration = min(max(middlePauseDuration, 0.1), 30)

        let balloon = BalloonProfile(
            id: UUID(),
            title: trimmedTitle.isEmpty ? "無題の風船" : trimmedTitle,
            text: trimmedText.isEmpty ? "🎈" : trimmedText,
            imageName: imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: position.name,
            pausesAtMiddle: pausesAtMiddle,
            middlePauseDuration: clampedPauseDuration,
            isEnabled: true,
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
        imageName: String?,
        colorName: String,
        positionName: String,
        pausesAtMiddle: Bool,
        middlePauseDuration: Double
    ) {
        guard let index = balloons.firstIndex(where: { $0.id == id }) else { return }

        let color = Self.colorOptions.first(where: { $0.name == colorName }) ?? Self.colorOptions[0]
        let position = Self.positionOptions.first(where: { $0.name == positionName }) ?? Self.positionOptions[1]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPauseDuration = min(max(middlePauseDuration, 0.1), 30)
        let createdAt = balloons[index].createdAt
        let isEnabled = balloons[index].isEnabled

        balloons[index] = BalloonProfile(
            id: id,
            title: trimmedTitle.isEmpty ? "無題の風船" : trimmedTitle,
            text: trimmedText.isEmpty ? "🎈" : trimmedText,
            imageName: imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: position.name,
            pausesAtMiddle: pausesAtMiddle,
            middlePauseDuration: clampedPauseDuration,
            isEnabled: isEnabled,
            createdAt: createdAt
        )
        activeBalloonID = id
        save()
    }

    func activateBalloon(id: UUID) {
        guard balloons.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        activeBalloonID = id
        save()
    }

    @discardableResult
    func activateNextEnabledBalloon() -> Bool {
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
        defaults.set(climbSpeed, forKey: Keys.climbSpeed)
        defaults.set(activeBalloonID?.uuidString, forKey: Keys.activeBalloonID)

        if let encoded = try? JSONEncoder().encode(balloons) {
            defaults.set(encoded, forKey: Keys.balloons)
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
            title: "最初の風船",
            text: text,
            imageName: imageName?.nilIfEmpty,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: "中央",
            pausesAtMiddle: false,
            middlePauseDuration: 1.0,
            isEnabled: true,
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
            title: "風船",
            text: "🎈",
            imageName: nil,
            colorName: color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            positionName: "中央",
            pausesAtMiddle: false,
            middlePauseDuration: 1.0,
            isEnabled: true,
            createdAt: Date()
        )
    }
}

private enum Keys {
    static let displayInterval = "displayInterval"
    static let climbSpeed = "climbSpeed"
    static let balloons = "balloons"
    static let activeBalloonID = "activeBalloonID"
    static let isPaused = "isPaused"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
