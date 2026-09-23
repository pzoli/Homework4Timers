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
    @Query(sort: \SavedIntervalList.createdAt, order: .reverse) private var savedLists: [SavedIntervalList]
    @StateObject private var viewModel = TimerSequenceViewModel()
    
    @AppStorage("didInsertSamples") private var didInsertSamples: Bool = false
    @AppStorage("activePresetID") private var activePresetIDString: String = ""
    @AppStorage("activePresetName") private var activePresetName: String = ""
    
    @State private var activeSheetItem: EditSheetItem? = nil
    @State private var isShowingPresetsSheet: Bool = false
    @State private var isShowingSaveAsNewAlert: Bool = false
    @State private var isShowingNewTemplateAlert: Bool = false
    @State private var isShowingSaveSuccessToast: Bool = false
    @State private var savePresetName: String = ""
    
    private var currentLoadedPreset: SavedIntervalList? {
        guard let uuid = UUID(uuidString: activePresetIDString) else { return nil }
        return savedLists.first(where: { $0.id == uuid })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                activePresetHeader
                runningStatusBox
                intervalListView
                actionButtons
            }
            .padding()
            .navigationTitle("Intervallum időzítő")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            Button {
                                isShowingPresetsSheet = true
                            } label: {
                                Label("Mentett sablonok...", systemImage: "folder")
                            }
                            
                            Divider()
                            
                            Button {
                                handleNewTemplateAction()
                            } label: {
                                Label("Új sablon", systemImage: "doc.badge.plus")
                            }
                            
                            Button {
                                handleSaveAction()
                            } label: {
                                Label(
                                    currentLoadedPreset != nil ? "Mentés (\(currentLoadedPreset!.name))" : "Mentés",
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                            .disabled(storedItems.isEmpty)
                            
                            Button {
                                savePresetName = activePresetName.isEmpty ? "" : "\(activePresetName) másolata"
                                isShowingSaveAsNewAlert = true
                            } label: {
                                Label("Mentés újként...", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(storedItems.isEmpty)
                        } label: {
                            Image(systemName: "folder")
                        }
                        
                        Button {
                            activeSheetItem = EditSheetItem(id: UUID().uuidString, entity: nil, defaultType: .interval)
                        } label: {
                            Image(systemName: "plus")
                        }
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
            .sheet(isPresented: $isShowingPresetsSheet) {
                SavedPresetsView(
                    currentItems: storedItems,
                    activePresetIDString: $activePresetIDString,
                    activePresetName: $activePresetName
                ) { preset in
                    loadPreset(preset)
                }
            }
            .alert("Mentés új sablonként", isPresented: $isShowingSaveAsNewAlert) {
                TextField("Sablon neve", text: $savePresetName)
                Button("Mégse", role: .cancel) { }
                Button("Mentés") {
                    saveAsNewPreset(name: savePresetName)
                }
                .disabled(savePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Add meg az új sablon nevét:")
            }
            .alert("Új üres sablon", isPresented: $isShowingNewTemplateAlert) {
                Button("Mégse", role: .cancel) { }
                Button("Új sablon létrehozása", role: .destructive) {
                    createNewEmptyTemplate()
                }
            } message: {
                Text("Biztosan új üres sablont szeretnél létrehozni? A munkaterület elemei törlődnek.")
            }
            .overlay(alignment: .bottom) {
                if isShowingSaveSuccessToast {
                    Text("Sablon sikeresen mentve!")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                if !didInsertSamples && storedItems.isEmpty {
                    for sample in TimerIntervalEntity.samples {
                        modelContext.insert(sample)
                    }
                    try? modelContext.save()
                    didInsertSamples = true
                }
                viewModel.bind(items: storedItems)
            }
            .onChange(of: storedItems) { _, newValue in
                viewModel.bind(items: newValue)
            }
        }
    }
    
    private var activePresetHeader: some View {
        HStack {
            Label {
                HStack(spacing: 4) {
                    Text("Betöltött sablon:")
                        .foregroundStyle(.secondary)
                    Text(activePresetName.isEmpty ? "Nincs (Egyéni)" : activePresetName)
                        .bold()
                        .foregroundStyle(activePresetName.isEmpty ? .secondary : .primary)
                }
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            
            Spacer()
            
            if currentLoadedPreset != nil && !storedItems.isEmpty {
                Button {
                    handleSaveAction()
                } label: {
                    Label("Mentés", systemImage: "square.and.arrow.down")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var runningStatusBox: some View {
        GroupBox {
            VStack(spacing: 8) {
                if let current = viewModel.currentLabel, viewModel.isRunning {
                    HStack {
                        Text(current)
                            .font(.title).bold()
                        Spacer()
                        if viewModel.isPaused {
                            Text("Felfüggesztve")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
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
    }
    
    private var intervalListView: some View {
        List {
            if storedItems.isEmpty {
                ContentUnavailableView(
                    "Nincs intervallum",
                    systemImage: "timer",
                    description: Text("Koppints a + gombra új intervallum vagy zárójel hozzáadásához, vagy tölts be egy mentett sablont.")
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
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                if viewModel.isPaused {
                    viewModel.resume()
                } else {
                    viewModel.start()
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled((viewModel.isRunning && !viewModel.isPaused) || viewModel.buildExecutionPlan(items: storedItems).isEmpty)
            .accessibilityLabel("Lejátszás")
            
            Button {
                viewModel.pause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!viewModel.isRunning || viewModel.isPaused)
            .accessibilityLabel("Felfüggesztés")
            
            Button {
                viewModel.stop()
            } label: {
                Image(systemName: "square.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.isRunning)
            .accessibilityLabel("Leállítás")
        }
    }
    
    private func handleSaveAction() {
        if let loadedPreset = currentLoadedPreset {
            loadedPreset.items = storedItems.map { SavedIntervalItem(from: $0) }
            try? modelContext.save()
            showToast()
        } else {
            savePresetName = activePresetName
            isShowingSaveAsNewAlert = true
        }
    }
    
    private func saveAsNewPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        let savedItems = storedItems.map { SavedIntervalItem(from: $0) }
        let newList = SavedIntervalList(name: trimmed, createdAt: Date(), items: savedItems)
        modelContext.insert(newList)
        try? modelContext.save()
        
        activePresetIDString = newList.id.uuidString
        activePresetName = trimmed
        showToast()
    }
    
    private func handleNewTemplateAction() {
        if storedItems.isEmpty {
            createNewEmptyTemplate()
        } else {
            isShowingNewTemplateAlert = true
        }
    }
    
    private func createNewEmptyTemplate() {
        if viewModel.isRunning {
            viewModel.stop()
        }
        for item in storedItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
        activePresetIDString = ""
        activePresetName = ""
        viewModel.bind(items: [])
    }
    
    private func loadPreset(_ preset: SavedIntervalList) {
        if viewModel.isRunning {
            viewModel.stop()
        }
        for item in storedItems {
            modelContext.delete(item)
        }
        let newEntities = preset.createTimerIntervalEntities()
        for entity in newEntities {
            modelContext.insert(entity)
        }
        try? modelContext.save()
        activePresetIDString = preset.id.uuidString
        activePresetName = preset.name
        viewModel.bind(items: newEntities)
    }
    
    private func showToast() {
        withAnimation {
            isShowingSaveSuccessToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    isShowingSaveSuccessToast = false
                }
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
        .modelContainer(for: [TimerIntervalEntity.self, SavedIntervalList.self], inMemory: true)
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
