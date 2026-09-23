import SwiftUI
import SwiftData
import Combine

struct EditSheetItem: Identifiable {
    let id: String
    let entity: TimerIntervalEntity?
    let defaultType: IntervalItemType
}

struct TimerContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimerIntervalEntity.createdAt) private var storedItems: [TimerIntervalEntity]
    @StateObject private var viewModel = TimerSequenceViewModel()
    
    @State private var activeSheetItem: EditSheetItem? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GroupBox {
                    VStack(spacing: 8) {
                        if let current = viewModel.currentLabel, viewModel.isRunning {
                            Text(current)
                                .font(.title).bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Hátralévő idő: \(formatTime(viewModel.remainingSeconds))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if let stepIdx = viewModel.currentStepIndex, let total = viewModel.totalStepsCount {
                                Text("Lépés \(stepIdx + 1)/\(total)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else if let idx = viewModel.progressIndex {
                                Text("Lépés \(idx + 1)/\(storedItems.count)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Nincs futó szakasz")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } label: {
                    Label("Futás állapota", systemImage: "timer")
                }
                
                List {
                    if storedItems.isEmpty {
                        ContentUnavailableView(
                            "Nincs intervallum",
                            systemImage: "timer",
                            description: Text("Koppints a + gombra új intervallum vagy zárójel hozzáadásához.")
                        )
                    } else {
                        ForEach(storedItems) { item in
                            rowContent(for: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activeSheetItem = EditSheetItem(id: item.id.uuidString, entity: item, defaultType: item.itemType)
                                }
                                .listRowBackground(rowBackground(for: item))
                                .padding(.leading, CGFloat(depth(of: item, in: storedItems)) * 16)
                        }
                        .onDelete(perform: delete)
                        .onMove(perform: move)
                    }
                }
                
                HStack(spacing: 16) {
                    Button("Start") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isRunning || viewModel.buildExecutionPlan(items: storedItems).isEmpty)
                    
                    Button("Stop") { viewModel.stop() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                        .disabled(!viewModel.isRunning)
                }
            }
            .padding()
            .navigationTitle("Intervallum időzítő")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheetItem = EditSheetItem(id: UUID().uuidString, entity: nil, defaultType: .interval)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheetItem) { sheetItem in
                IntervalEditSheet(itemToEdit: sheetItem.entity, initialType: sheetItem.defaultType) { type, minutes, label, repeatCount in
                    if let item = sheetItem.entity {
                        item.itemType = type
                        item.minutes = minutes
                        item.label = label
                        item.repeatCount = repeatCount
                        try? modelContext.save()
                    } else {
                        let lastDate = storedItems.last?.createdAt ?? Date()
                        let newDate = max(Date(), lastDate.addingTimeInterval(1))
                        let new = TimerIntervalEntity(
                            minutes: minutes,
                            label: label,
                            itemType: type,
                            repeatCount: repeatCount,
                            createdAt: newDate
                        )
                        modelContext.insert(new)
                        try? modelContext.save()
                    }
                }
            }
            .onAppear {
                if storedItems.isEmpty {
                    for sample in TimerIntervalEntity.samples {
                        modelContext.insert(sample)
                    }
                    try? modelContext.save()
                }
                viewModel.bind(items: storedItems)
            }
            .onChange(of: storedItems) { _, newValue in
                viewModel.bind(items: newValue)
            }
        }
    }
    
    @ViewBuilder
    private func rowContent(for item: TimerIntervalEntity) -> some View {
        HStack {
            switch item.itemType {
            case .interval:
                Text("\(item.minutes) perc")
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if !item.label.isEmpty {
                    Text(item.label)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            case .openBracket:
                Text("(")
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.blue)
                    .frame(width: 20, alignment: .center)
                Text("Nyitó zárójel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .closeBracket:
                Text(")")
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.blue)
                    .frame(width: 20, alignment: .center)
                Text("\(item.repeatCount)× ismétlés")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "pencil")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private func depth(of targetItem: TimerIntervalEntity, in items: [TimerIntervalEntity]) -> Int {
        var currentDepth = 0
        for item in items {
            if item.id == targetItem.id {
                if item.itemType == .closeBracket {
                    return max(0, currentDepth - 1)
                }
                return currentDepth
            }
            if item.itemType == .openBracket {
                currentDepth += 1
            } else if item.itemType == .closeBracket {
                currentDepth = max(0, currentDepth - 1)
            }
        }
        return 0
    }
    
    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(storedItems[index]) }
        try? modelContext.save()
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        var revisedItems = storedItems
        revisedItems.move(fromOffsets: source, toOffset: destination)
        for (index, item) in revisedItems.enumerated() {
            item.createdAt = Date().addingTimeInterval(TimeInterval(index))
        }
        try? modelContext.save()
    }
    
    private func rowBackground(for item: TimerIntervalEntity) -> Color? {
        if let idx = viewModel.progressIndex, viewModel.isRunning {
            let current = storedItems[idx]
            return current.id == item.id ? Color.yellow.opacity(0.2) : nil
        }
        return nil
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct IntervalEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let itemToEdit: TimerIntervalEntity?
    let initialType: IntervalItemType
    let onSave: (IntervalItemType, Int, String, Int) -> Void
    
    @State private var itemType: IntervalItemType
    @State private var minutesText: String
    @State private var labelText: String
    @State private var repeatCount: Int
    
    init(
        itemToEdit: TimerIntervalEntity?,
        initialType: IntervalItemType = .interval,
        onSave: @escaping (IntervalItemType, Int, String, Int) -> Void
    ) {
        self.itemToEdit = itemToEdit
        self.initialType = initialType
        self.onSave = onSave
        
        let type = itemToEdit?.itemType ?? initialType
        _itemType = State(initialValue: type)
        _minutesText = State(initialValue: itemToEdit != nil ? "\(itemToEdit!.minutes)" : "1")
        _labelText = State(initialValue: itemToEdit?.label ?? "")
        _repeatCount = State(initialValue: itemToEdit?.repeatCount ?? 2)
    }
    
    private var isFormValid: Bool {
        switch itemType {
        case .interval:
            if let m = Int(minutesText), m > 0 {
                return true
            }
            return false
        case .openBracket:
            return true
        case .closeBracket:
            return repeatCount >= 1
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Elem típusa")) {
                    Picker("Típus", selection: $itemType) {
                        Text("Intervallum").tag(IntervalItemType.interval)
                        Text("Nyitó (").tag(IntervalItemType.openBracket)
                        Text("Záró )").tag(IntervalItemType.closeBracket)
                    }
                    .pickerStyle(.segmented)
                }
                
                switch itemType {
                case .interval:
                    Section(header: Text("Intervallum adatok")) {
                        HStack {
                            Text("Perc")
                            Spacer()
                            TextField("Perc", text: $minutesText)
                                .applyNumberPadKeyboard()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        
                        HStack {
                            Text("Címke")
                            Spacer()
                            TextField("Címke", text: $labelText)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                case .openBracket:
                    Section {
                        Text("Nyitó zárójel ( megadása a csoportos ismétlés kezdéséhez.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .closeBracket:
                    Section(header: Text("Ismétlés beállításai")) {
                        Stepper("Ismétlések száma: \(repeatCount)", value: $repeatCount, in: 1...99)
                        Text("A nyitó és záró zárójel közötti intervallumok ennyiszer fognak megismétlődni.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(itemToEdit == nil ? "Új felvétel" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(itemToEdit == nil ? "Hozzáadás" : "Mentés") {
                        let m = Int(minutesText) ?? 1
                        let l = labelText.trimmingCharacters(in: .whitespaces)
                        onSave(itemType, m, l, repeatCount)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
}

#Preview {
    TimerContentView()
        .modelContainer(for: TimerIntervalEntity.self, inMemory: true)
}

private extension View {
    @ViewBuilder
    func applyNumberPadKeyboard() -> some View {
        #if canImport(UIKit)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
