import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SavedPresetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \SavedIntervalList.createdAt, order: .reverse) private var savedLists: [SavedIntervalList]
    
    let currentItems: [TimerIntervalEntity]
    @Binding var activePresetIDString: String
    @Binding var activePresetName: String
    let onLoadPreset: (SavedIntervalList) -> Void
    
    @State private var isShowingSaveCurrentAlert: Bool = false
    @State private var newPresetName: String = ""
    
    @State private var presetToRename: SavedIntervalList? = nil
    @State private var renameText: String = ""
    
    // Import & Export State
    @State private var isShowingImportPicker: Bool = false
    @State private var isShowingExportPicker: Bool = false
    @State private var exportDocument: PresetsDocument? = nil
    @State private var exportDefaultFilename: String = "sablonok.json"
    
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isShowingInfoAlert: Bool = false
    
    @State private var isShowingToast: Bool = false
    @State private var toastMessage: String = ""
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Mentett sablonok")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { saveAsNewButtonInset }
                .alert("Sorozat mentése újként", isPresented: $isShowingSaveCurrentAlert) {
                    saveCurrentAlertActions
                } message: {
                    Text("Add meg az új menteni kívánt intervallum sorozat nevét:")
                }
                .alert("Név szerkesztése", isPresented: renameBinding) {
                    renameAlertActions
                } message: {
                    Text("Add meg a sablon új nevét:")
                }
                .alert(alertTitle, isPresented: $isShowingInfoAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(alertMessage)
                }
                .fileImporter(
                    isPresented: $isShowingImportPicker,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false,
                    onCompletion: handleImport
                )
                .fileExporter(
                    isPresented: $isShowingExportPicker,
                    document: exportDocument,
                    contentType: .json,
                    defaultFilename: exportDefaultFilename,
                    onCompletion: handleExportResult
                )
                .overlay(alignment: .bottom) { toastOverlay }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if savedLists.isEmpty {
            ContentUnavailableView {
                Label("Nincsenek mentett sablonok", systemImage: "square.and.arrow.down")
            } description: {
                Text("Mentsd el a jelenlegi intervallum sorozatodat, vagy importálj sablonokat JSON fájlból.")
            } actions: {
                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Sablonok importálása", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(savedLists) { list in
                    presetRow(for: list)
                }
                .onDelete(perform: deletePresets)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Bezárás") {
                dismiss()
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Importálás...", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    exportAllPresets()
                } label: {
                    Label("Összes exportálása...", systemImage: "square.and.arrow.up")
                }
                .disabled(savedLists.isEmpty)
                
                Divider()
                
                Button {
                    newPresetName = ""
                    isShowingSaveCurrentAlert = true
                } label: {
                    Label("Jelenlegi mentése újként", systemImage: "plus")
                }
                .disabled(currentItems.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
            }
        }
    }
    
    @ViewBuilder
    private var saveAsNewButtonInset: some View {
        if !currentItems.isEmpty {
            Button {
                newPresetName = ""
                isShowingSaveCurrentAlert = true
            } label: {
                Label("Mentés új sablonként", systemImage: "square.and.arrow.down.on.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.ultraThinMaterial)
        }
    }
    
    @ViewBuilder
    private var saveCurrentAlertActions: some View {
        TextField("Sablon neve", text: $newPresetName)
        Button("Mégse", role: .cancel) { }
        Button("Mentés") {
            saveCurrentSequence(name: newPresetName)
        }
        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    
    private var renameBinding: Binding<Bool> {
        Binding(
            get: { presetToRename != nil },
            set: { if !$0 { presetToRename = nil } }
        )
    }
    
    @ViewBuilder
    private var renameAlertActions: some View {
        TextField("Új név", text: $renameText)
        Button("Mégse", role: .cancel) {
            presetToRename = nil
        }
        Button("Mentés") {
            if let target = presetToRename {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if target.id.uuidString == activePresetIDString {
                        activePresetName = trimmed
                    }
                    target.name = trimmed
                    try? modelContext.save()
                }
            }
            presetToRename = nil
        }
        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    
    @ViewBuilder
    private var toastOverlay: some View {
        if isShowingToast {
            Text(toastMessage)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.8))
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private func presetRow(for list: SavedIntervalList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.headline)
                    
                    if list.id.uuidString == activePresetIDString {
                        Text("Aktív")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 8) {
                    Text("\(list.items.count) elem")
                    Text("•")
                    Text(list.createdAt.formatted(date: .numeric, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    exportSinglePreset(list)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Exportálás")
                
                Button {
                    renameText = list.name
                    presetToRename = list
                } label: {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Név szerkesztése")
                
                Button {
                    onLoadPreset(list)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                        Text(list.id.uuidString == activePresetIDString ? "Újratöltés" : "Betöltés")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onLoadPreset(list)
                dismiss()
            } label: {
                Label("Visszatöltés", systemImage: "arrow.down.doc")
            }
            
            Button {
                exportSinglePreset(list)
            } label: {
                Label("Exportálás...", systemImage: "square.and.arrow.up")
            }
            
            Button {
                renameText = list.name
                presetToRename = list
            } label: {
                Label("Név szerkesztése", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                if list.id.uuidString == activePresetIDString {
                    activePresetIDString = ""
                    activePresetName = ""
                }
                modelContext.delete(list)
                try? modelContext.save()
            } label: {
                Label("Törlés", systemImage: "trash")
            }
        }
    }
    
    private func exportSinglePreset(_ list: SavedIntervalList) {
        let dto = PresetDTO(from: list)
        exportDocument = PresetsDocument(presets: [dto])
        let safeName = list.name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        exportDefaultFilename = safeName.isEmpty ? "sablon.json" : "\(safeName).json"
        isShowingExportPicker = true
    }
    
    private func exportAllPresets() {
        let dtos = savedLists.map { PresetDTO(from: $0) }
        exportDocument = PresetsDocument(presets: dtos)
        exportDefaultFilename = "mentett_sablonok.json"
        isShowingExportPicker = true
    }
    
    private func handleExportResult(result: Result<URL, Error>) {
        switch result {
        case .success:
            showToast("Sablon(ok) sikeresen exportálva!")
        case .failure(let error):
            alertTitle = "Exportálási hiba"
            alertMessage = error.localizedDescription
            isShowingInfoAlert = true
        }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let dtos = try PresetDTO.decodePresets(from: data)
                guard !dtos.isEmpty else {
                    alertTitle = "Hiba"
                    alertMessage = "A fájl nem tartalmaz érvényes sablont."
                    isShowingInfoAlert = true
                    return
                }
                
                var importedCount = 0
                for dto in dtos {
                    let newPreset = dto.toSavedIntervalList()
                    if savedLists.contains(where: { $0.id == newPreset.id }) {
                        newPreset.id = UUID()
                    }
                    modelContext.insert(newPreset)
                    importedCount += 1
                }
                try modelContext.save()
                showToast("\(importedCount) sablon sikeresen importálva!")
            } catch {
                alertTitle = "Importálási hiba"
                alertMessage = "Nem sikerült a fájl beolvasása: \(error.localizedDescription)"
                isShowingInfoAlert = true
            }
        case .failure(let error):
            alertTitle = "Importálási hiba"
            alertMessage = error.localizedDescription
            isShowingInfoAlert = true
        }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation {
            isShowingToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation {
                    isShowingToast = false
                }
            }
        }
    }
    
    private func saveCurrentSequence(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let savedItems = currentItems.map { SavedIntervalItem(from: $0) }
        let newPreset = SavedIntervalList(name: trimmedName, createdAt: Date(), items: savedItems)
        
        modelContext.insert(newPreset)
        try? modelContext.save()
        activePresetIDString = newPreset.id.uuidString
        activePresetName = trimmedName
    }
    
    private func deletePresets(at offsets: IndexSet) {
        for index in offsets {
            let list = savedLists[index]
            if list.id.uuidString == activePresetIDString {
                activePresetIDString = ""
                activePresetName = ""
            }
            modelContext.delete(list)
        }
        try? modelContext.save()
    }
}
