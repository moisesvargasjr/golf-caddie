import SwiftUI

struct ShotEditView: View {
    let shot: Shot
    let bag: [ClubID]
    let onDelete: () -> Void

    @State private var club: ClubID?
    @State private var notes: String = ""
    @State private var saveError: String?
    @State private var showDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Shot") {
                LabeledContent("Sequence") { Text("\(shot.sequenceNumber)").monospacedDigit() }
                LabeledContent("Time") {
                    Text(shot.timestamp, format: .dateTime.hour().minute().second())
                }
                LabeledContent("Source") { Text(sourceLabel) }
                LabeledContent("Has GPS") { Text(shot.hadGPS ? "Yes" : "No") }
                if let acc = shot.gpsAccuracy {
                    LabeledContent("Accuracy") {
                        Text(String(format: "±%.1fm", acc)).monospacedDigit()
                    }
                }
                if let lat = shot.latitude, let lng = shot.longitude {
                    LabeledContent("Coordinates") {
                        Text(String(format: "%.5f, %.5f", lat, lng))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }

            Section("Club") {
                Picker("Club", selection: $club) {
                    Text("(no club)").tag(ClubID?.none)
                    ForEach(bag) { c in
                        Text(c.longName).tag(ClubID?.some(c))
                    }
                }
            }

            Section("Notes") {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3 ... 8)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete Shot")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if let saveError {
                Section {
                    Text(saveError).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Shot \(shot.sequenceNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this shot?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This cannot be undone. Subsequent shots in this hole will be renumbered.")
        }
        .onAppear {
            club = shot.club
            notes = shot.notes ?? ""
        }
        .onDisappear {
            saveIfChanged()
        }
    }

    private var sourceLabel: String {
        switch shot.source {
        case .button: return "On-screen"
        case .actionButton: return "Action button"
        case .manual: return "Manual entry"
        }
    }

    private func saveIfChanged() {
        let originalNotes = shot.notes ?? ""
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNew: String? = trimmed.isEmpty ? nil : trimmed
        let normalizedOriginal: String? = originalNotes.isEmpty ? nil : originalNotes
        if club == shot.club, normalizedNew == normalizedOriginal { return }
        var updated = shot
        updated.club = club
        updated.notes = normalizedNew
        do {
            try ShotRepository.update(updated)
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
