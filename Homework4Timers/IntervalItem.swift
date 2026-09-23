import Foundation
import SwiftData

enum IntervalItemType: String, Codable, CaseIterable {
    case interval = "interval"
    case openBracket = "openBracket"
    case closeBracket = "closeBracket"
}

@Model
final class TimerIntervalEntity: Identifiable, Hashable {
    var id: UUID = UUID()
    var minutes: Int = 0
    var label: String = ""
    var createdAt: Date = Date()
    var itemTypeRaw: String = "interval"
    var repeatCount: Int = 1
    
    var itemType: IntervalItemType {
        get { IntervalItemType(rawValue: itemTypeRaw) ?? .interval }
        set { itemTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        minutes: Int = 0,
        label: String = "",
        itemType: IntervalItemType = .interval,
        repeatCount: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.minutes = minutes
        self.label = label
        self.itemTypeRaw = itemType.rawValue
        self.repeatCount = repeatCount
        self.createdAt = createdAt
    }

    static func == (lhs: TimerIntervalEntity, rhs: TimerIntervalEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension TimerIntervalEntity {
    static let samples: [TimerIntervalEntity] = [
        TimerIntervalEntity(minutes: 1, label: "Bemelegítés", createdAt: Date().addingTimeInterval(0)),
        TimerIntervalEntity(itemType: .openBracket, createdAt: Date().addingTimeInterval(1)),
        TimerIntervalEntity(minutes: 2, label: "Fő szakasz", createdAt: Date().addingTimeInterval(2)),
        TimerIntervalEntity(itemType: .closeBracket, repeatCount: 3, createdAt: Date().addingTimeInterval(3)),
        TimerIntervalEntity(minutes: 1, label: "Levezetés", createdAt: Date().addingTimeInterval(4))
    ]
}
