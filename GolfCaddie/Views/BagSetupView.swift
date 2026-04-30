import SwiftUI

struct BagSetupView: View {
    @State private var bag: [ClubID]
    @State private var saveError: String?
    private let onSave: ([ClubID]) -> Void
    private let onCancel: (() -> Void)?

    init(initialBag: [ClubID], onCancel: (() -> Void)? = nil, onSave: @escaping ([ClubID]) -> Void) {
        let seed = initialBag.isEmpty ? ClubConfiguration.recommendedDefault.bag : initialBag
        _bag = State(initialValue: seed)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var availableClubs: [ClubID] {
        ClubID.allCases.filter { !bag.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                if bag.isEmpty {
                    Text("Tap a club below to add it to your bag.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bag, id: \.self) { club in
                        Text(club.longName)
                    }
                    .onDelete { indices in bag.remove(atOffsets: indices) }
                    .onMove { from, to in bag.move(fromOffsets: from, toOffset: to) }
                }
            } header: {
                Text("Your Bag (\(bag.count) of 14)")
            } footer: {
                Text("USGA rules allow up to 14 clubs. Drag to reorder; swipe to remove.")
            }

            if !availableClubs.isEmpty {
                Section("Add Club") {
                    ForEach(availableClubs, id: \.self) { club in
                        let canAdd = bag.count < 14
                        Button {
                            guard canAdd else { return }
                            bag.append(club)
                        } label: {
                            HStack {
                                Text(club.longName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)
                            }
                        }
                        .disabled(!canAdd)
                    }
                }
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("My Bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            if let onCancel {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    save()
                } label: {
                    Text("Save Bag")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(bag.isEmpty)
            }
        }
    }

    private func save() {
        do {
            try ClubConfigurationRepository.save(ClubConfiguration(bag: bag))
            onSave(bag)
        } catch {
            saveError = "Couldn't save bag: \(error.localizedDescription)"
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        BagSetupView(initialBag: []) { _ in }
    }
}

#Preview("Configured") {
    NavigationStack {
        BagSetupView(initialBag: ClubConfiguration.recommendedDefault.bag) { _ in }
    }
}
