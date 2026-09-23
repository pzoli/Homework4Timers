import SwiftUI
import SwiftData

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
    
    var body: some View {
        NavigationStack {
            Group {
                if savedLists.isEmpty {
                    ContentUnavailableView(
                        "Nincsenek mentett sablonok",
                        systemImage: "square.and.arrow.down",
                        description: Text("Mentsd el a jelenlegi intervallum sorozatodat a jobb felső gombra vagy a lent található mentés gombra koppintva.")
                    )
                } else {
                    List {
                        ForEach(savedLists) { list in
                            presetRow(for: list)
                        }
                        .onDelete(perform: deletePresets)
                    }
                }
            }
            .navigationTitle("Mentett sablonok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezárás") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPresetName = ""
                        isShowingSaveCurrentAlert = true
                    } label: {
                        Label("Jelenlegi mentése újként", systemImage: "plus")
                    }
                    .disabled(currentItems.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
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
            .alert("Sorozat mentése újként", isPresented: $isShowingSaveCurrentAlert) {
                TextField("Sablon neve", text: $newPresetName)
                Button("Mégse", role: .cancel) { }
                Button("Mentés") {
                    saveCurrentSequence(name: newPresetName)
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Add meg az új menteni kívánt intervallum sorozat nevét:")
            }
            .alert("Név szerkesztése", isPresented: Binding(
                get: { presetToRename != nil },
                set: { if !$0 { presetToRename = nil } }
            )) {
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
            } message: {
                Text("Add meg a sablon új nevét:")
            }
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
