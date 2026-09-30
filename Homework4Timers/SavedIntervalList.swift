import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Import / Export DTOs & Document

struct PresetItemDTO: Codable, Identifiable {
    var id: UUID
    var itemType: String
    var label: String
    var minutes: Int
    var repeatCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case itemType
        case label
        case minutes
        case repeatCount
    }

    init(id: UUID = UUID(), itemType: String, label: String, minutes: Int, repeatCount: Int) {
        self.id = id
        self.itemType = itemType
        self.label = label
        self.minutes = minutes
        self.repeatCount = repeatCount
    }

    init(from item: SavedIntervalItem) {
        self.id = item.id
        self.minutes = item.minutes
        self.label = item.label
        self.repeatCount = item.repeatCount
        switch item.itemType {
        case .interval:
            self.itemType = "INTERVAL"
        case .openBracket:
            self.itemType = "OPEN_BRACKET"
        case .closeBracket:
            self.itemType = "CLOSE_BRACKET"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let uuidString = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: uuidString) {
            self.id = uuid
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            self.id = UUID()
        }

        self.itemType = (try? container.decode(String.self, forKey: .itemType)) ?? "INTERVAL"
        self.label = (try? container.decode(String.self, forKey: .label)) ?? ""
        self.minutes = (try? container.decode(Int.self, forKey: .minutes)) ?? 0
        self.repeatCount = (try? container.decode(Int.self, forKey: .repeatCount)) ?? 1
    }

    func toSavedIntervalItem() -> SavedIntervalItem {
        let type: IntervalItemType
        switch itemType.uppercased() {
        case "OPEN_BRACKET", "OPENBRACKET":
            type = .openBracket
        case "CLOSE_BRACKET", "CLOSEBRACKET":
            type = .closeBracket
        default:
            type = .interval
        }
        return SavedIntervalItem(
            id: id,
            minutes: minutes,
            label: label,
            itemType: type,
            repeatCount: repeatCount
        )
    }
}

struct PresetDTO: Codable, Identifiable {
    var createdAt: Int64
    var id: UUID
    var items: [PresetItemDTO]
    var name: String

    enum CodingKeys: String, CodingKey {
        case createdAt
        case id
        case items
        case name
    }

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), items: [PresetItemDTO] = []) {
        self.id = id
        self.name = name
        self.createdAt = Int64(createdAt.timeIntervalSince1970 * 1000)
        self.items = items
    }

    init(from list: SavedIntervalList) {
        self.id = list.id
        self.name = list.name
        self.createdAt = Int64(list.createdAt.timeIntervalSince1970 * 1000)
        self.items = list.items.map { PresetItemDTO(from: $0) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let doubleVal = try? container.decode(Double.self, forKey: .createdAt) {
            self.createdAt = Int64(doubleVal)
        } else if let intVal = try? container.decode(Int64.self, forKey: .createdAt) {
            self.createdAt = intVal
        } else {
            self.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        }

        if let uuidString = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: uuidString) {
            self.id = uuid
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            self.id = UUID()
        }

        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Importált sablon"
        self.items = (try? container.decode([PresetItemDTO].self, forKey: .items)) ?? []
    }

    func toSavedIntervalList() -> SavedIntervalList {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
        let savedItems = items.map { $0.toSavedIntervalItem() }
        return SavedIntervalList(
            id: id,
            name: name,
            createdAt: date,
            items: savedItems
        )
    }

    static func decodePresets(from data: Data) throws -> [PresetDTO] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([PresetDTO].self, from: data) {
            return list
        }
        if let single = try? decoder.decode(PresetDTO.self, from: data) {
            return [single]
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Érvénytelen sablon JSON formátum."))
    }

    static func encodePresets(_ presets: [PresetDTO]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presets)
    }
}

struct PresetsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var presets: [PresetDTO]

    init(presets: [PresetDTO] = []) {
        self.presets = presets
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.presets = try PresetDTO.decodePresets(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try PresetDTO.encodePresets(presets)
        return FileWrapper(regularFileWithContents: data)
    }
}
