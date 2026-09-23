import SwiftUI
import SwiftData
import Combine

struct TimerContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimerIntervalEntity.createdAt) private var storedItems: [TimerIntervalEntity]
    @StateObject private var viewModel = TimerSequenceViewModel()
    
    @State private var selectedItemForEdit: TimerIntervalEntity? = nil
    @State private var isSheetPresented: Bool = false
    
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
                            if let idx = viewModel.progressIndex {
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
                    ForEach(storedItems) { item in
                        Button {
                            selectedItemForEdit = item
                            isSheetPresented = true
                        } label: {
                            HStack {
                                Text("\(item.minutes) perc")
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                Text(item.label)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(rowBackground(for: item))
                    }
                    .onDelete(perform: delete)
                }
                
                HStack(spacing: 16) {
                    Button("Start") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isRunning || storedItems.isEmpty)
                    
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
                        selectedItemForEdit = nil
                        isSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isSheetPresented) {
                IntervalEditSheet(itemToEdit: selectedItemForEdit) { minutes, label in
                    if let item = selectedItemForEdit {
                        item.minutes = minutes
                        item.label = label
                    } else {
                        let new = TimerIntervalEntity(minutes: minutes, label: label)
                        modelContext.insert(new)
                    }
                }
            }
            .onAppear { viewModel.bind(items: storedItems) }
            .onChange(of: storedItems) { _, newValue in
                viewModel.bind(items: newValue)
            }
        }
    }
    
    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(storedItems[index]) }
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
    let onSave: (Int, String) -> Void
    
    @State private var minutesText: String = ""
    @State private var labelText: String = ""
    
    init(itemToEdit: TimerIntervalEntity?, onSave: @escaping (Int, String) -> Void) {
        self.itemToEdit = itemToEdit
        self.onSave = onSave
        _minutesText = State(initialValue: itemToEdit != nil ? "\(itemToEdit!.minutes)" : "")
        _labelText = State(initialValue: itemToEdit?.label ?? "")
    }
    
    private var isFormValid: Bool {
        if let m = Int(minutesText), m > 0, !labelText.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return false
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                        if let m = Int(minutesText) {
                            onSave(m, labelText.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        }
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
