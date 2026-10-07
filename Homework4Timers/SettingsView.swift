import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoContinueNextInterval") private var autoContinueNextInterval: Bool = false
    @AppStorage("appLanguage") private var appLanguage: String = "hu"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Nyelv")) {
                    Picker("Alkalmazás nyelve", selection: $appLanguage) {
                        Text("Magyar").tag("hu")
                        Text("English").tag("en")
                    }
                    .onChange(of: appLanguage) { _, newValue in
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                }
                
                Section(
                    header: Text("Időzítő működése"),
                    footer: Text("Ha az automatikus folytatás be van kapcsolva, a következő időintervallum visszaszámlálása az előző lejárta után azonnal elindul. Ha ki van kapcsolva, a rendszer megvárja a felhasználói nyugtázást.")
                ) {
                    Toggle("Automatikus folytatás", isOn: $autoContinueNextInterval)
                }
            }
            .navigationTitle("Beállítások")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, Locale(identifier: appLanguage))
        .id(appLanguage)
    }
}

#Preview {
    SettingsView()
}
