import SwiftUI

struct GlassesSettingsView: View {
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Glasses server", isOn: $glassesEnabled)
                } header: {
                    Text("Even Realities G2")
                } footer: {
                    Text("""
                    Serves the live round to the GolfCaddie glasses app over \
                    127.0.0.1:\(GlassesServer.port) (this phone only — nothing \
                    leaves the device). Turn on before a round if you're \
                    wearing the glasses. Tracking survives the screen locking \
                    while a round is active.
                    """)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    GlassesSettingsView(onDone: {})
}
