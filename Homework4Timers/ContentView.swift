import SwiftUI
import SwiftData
import Combine

struct TimerContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimerIntervalEntity.createdAt) private var storedItems: [TimerIntervalEntity]
    @StateObject private var viewModel = TimerSequenceViewModel()
    
    @State private var minutesText: String = ""
    @State private var labelText: String = ""
    
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
                        HStack {
                            Text("\(item.minutes) perc")
                                .monospacedDigit()
                            Text(item.label)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .listRowBackground(rowBackground(for: item))
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
                
                HStack {
                    TextField("Perc", text: $minutesText)
                        .applyNumberPadKeyboard()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("Címke", text: $labelText)
                        .textFieldStyle(.roundedBorder)
                    Button("Hozzáadás") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdd)
                }
                
                HStack {
                    Button("Start") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning || storedItems.isEmpty)
                    Button("Stop") { viewModel.stop() }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRunning)
                }
            }
            .padding()
            .navigationTitle("Intervallum időzítő")
            .toolbar { EditButton() }
            .onAppear { viewModel.bind(items: storedItems) }
            .onChange(of: storedItems) { _, newValue in
                viewModel.bind(items: newValue)
            }
        }
    }
    
    private var canAdd: Bool {
        if let m = Int(minutesText), m > 0, !labelText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }
    
    private func add() {
        guard let m = Int(minutesText), m > 0 else { return }
        let item = TimerIntervalEntity(minutes: m, label: labelText.trimmingCharacters(in: .whitespaces))
        modelContext.insert(item)
        minutesText = ""
        labelText = ""
    }
    
    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(storedItems[index]) }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        // Ha tartós sorrendre van szükség, adjunk orderIndex mezőt a modellhez.
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
