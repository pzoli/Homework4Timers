import Foundation
import SwiftData

@Model
final class TimerIntervalEntity: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var minutes: Int
    var label: String
    var createdAt: Date
    
    init(id: UUID = UUID(), minutes: Int, label: String, createdAt: Date = Date()) {
        self.id = id
        self.minutes = minutes
        self.label = label
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
        TimerIntervalEntity(minutes: 2, label: "Fő szakasz", createdAt: Date().addingTimeInterval(1)),
        TimerIntervalEntity(minutes: 1, label: "Levezetés", createdAt: Date().addingTimeInterval(2))
    ]
}
