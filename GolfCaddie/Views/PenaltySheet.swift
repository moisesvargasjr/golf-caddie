import SwiftUI

struct PenaltySheet: View {
    let onPick: (PenaltyType) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PenaltyType.allCases) { type in
                        Button {
                            onPick(type)
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("+1 stroke")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                    }
                } footer: {
                    Text("Each penalty adds 1 stroke. Edit later in hole review if needed.")
                }
            }
            .navigationTitle("Add Penalty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

#Preview {
    PenaltySheet(onPick: { _ in }, onCancel: {})
}
