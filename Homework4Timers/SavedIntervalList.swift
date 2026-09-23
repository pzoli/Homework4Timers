import Foundation
import SwiftData

struct SavedIntervalItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var minutes: Int = 0
    var label: String = ""
    var itemTypeRaw: String = "interval"
    var repeatCount: Int = 1

    var itemType: IntervalItemType {
        get { IntervalItemType(rawValue: itemTypeRaw) ?? .interval }
        set { itemTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), minutes: Int = 0, label: String = "", itemType: IntervalItemType = .interval, repeatCount: Int = 1) {
        self.id = id
        self.minutes = minutes
        self.label = label
        self.itemTypeRaw = itemType.rawValue
        self.repeatCount = repeatCount
    }

    init(from entity: TimerIntervalEntity) {
        self.id = entity.id
        self.minutes = entity.minutes
        self.label = entity.label
        self.itemTypeRaw = entity.itemTypeRaw
        self.repeatCount = entity.repeatCount
    }
}

@Model
final class SavedIntervalList: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var itemsData: Data = Data()

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), items: [SavedIntervalItem] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }

    var items: [SavedIntervalItem] {
        get {
            (try? JSONDecoder().decode([SavedIntervalItem].self, from: itemsData)) ?? []
        }
        set {
            itemsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func createTimerIntervalEntities() -> [TimerIntervalEntity] {
        let baseDate = Date()
        return items.enumerated().map { index, item in
            TimerIntervalEntity(
                id: UUID(),
                minutes: item.minutes,
                label: item.label,
                itemType: item.itemType,
                repeatCount: item.repeatCount,
                createdAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
    }
}
