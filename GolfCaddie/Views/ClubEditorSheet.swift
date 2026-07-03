import SwiftUI

/// Paper-styled club editor (B33). EDIT mode renames/retunes any catalog club
/// (seed rows included) or deletes it; CREATE mode adds a custom one. Club
/// edits persist immediately via `ClubRepository` — deliberately unlike the
/// host BagSetupView, whose bag composition only applies on its main Save.
struct ClubEditorSheet: View {
    /// Doubles as the host's `.sheet(item:)` driver.
    enum Mode: Identifiable {
        case create
        case edit(Club)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let club): return club.id
            }
        }
    }

    let mode: Mode
    /// Successful save — the host patches its copies in place (a renamed club
    /// must update its bag entry too) and dismisses.
    let onSaved: (Club) -> Void
    /// Successful delete/archive — the host drops the id from its bag and
    /// dismisses.
    let onDeleted: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var shortName: String
    @State private var kind: ClubKind
    @State private var yardsText: String
    @State private var actionError: String?
    @State private var showDeleteConfirm = false

    /// Active clubs EXCLUDING the edited one — the `ClubValidation` collision
    /// set. Loaded once; this sheet is the only catalog writer while it's up.
    private let others: [Club]

    @Environment(\.palette) private var palette

    init(mode: Mode, onSaved: @escaping (Club) -> Void,
         onDeleted: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onCancel = onCancel

        let active = (try? ClubRepository.all()) ?? []
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _shortName = State(initialValue: "")
            _kind = State(initialValue: .iron)
            _yardsText = State(initialValue: String(Club.defaultYards(for: .iron)))
            others = active
        case .edit(let club):
            _name = State(initialValue: club.name)
            _shortName = State(initialValue: club.shortName)
            _kind = State(initialValue: club.kind)
            _yardsText = State(initialValue: String(club.defaultYards))
            others = active.filter { $0.id != club.id }
        }
    }

    private var editedClub: Club? {
        if case .edit(let club) = mode { return club }
        return nil
    }

    // MARK: - Validation

    private var problems: [ClubValidation.Problem] {
        ClubValidation.problems(name: name, shortName: shortName, others: others)
    }

    private var nameProblems: [ClubValidation.Problem] {
        problems.filter { $0 == .nameEmpty || $0 == .nameTooLong }
    }

    private var shortNameProblems: [ClubValidation.Problem] {
        problems.filter { $0 != .nameEmpty && $0 != .nameTooLong }
    }

    private var parsedYards: Int? {
        Int(yardsText.trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool { problems.isEmpty && (parsedYards ?? 0) > 0 }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                navRow
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        section("Name") {
                            paperField("e.g. 7 Wood", text: $name)
                            problemLines(nameProblems)
                        }

                        section("Short name") {
                            paperField("e.g. 7W", text: $shortName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            problemLines(shortNameProblems)
                            hint("Shown on the watch keys — \(ClubValidation.maxShortNameLength) characters max.")
                        }

                        section("Kind") {
                            kindMenu
                        }

                        section("Default carry") {
                            carryField
                            if (parsedYards ?? 0) <= 0 {
                                problemText("Enter a number of yards")
                            }
                            hint("Shown on the watch until this club has real shot history.")
                        }

                        if let actionError {
                            problemText(actionError)
                        }

                        if editedClub != nil {
                            deleteButton
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 40)
                }
            }
        }
        // CREATE: carry tracks the kind prefill until the user types their own
        // number (i.e. while the text still equals the outgoing kind's default).
        .onChange(of: kind) { oldKind, newKind in
            guard case .create = mode else { return }
            if yardsText == String(Club.defaultYards(for: oldKind)) {
                yardsText = String(Club.defaultYards(for: newKind))
            }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            Text(deleteDialogMessage)
        }
        .presentationBackground(palette.paper)
        .themedRoot()
    }

    // MARK: - Top

    private var navRow: some View {
        HStack {
            Button { onCancel() } label: {
                Text("‹ CANCEL")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            Button { save() } label: {
                Text("SAVE ›")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(canSave ? palette.flag : palette.ink3)
            }
            .disabled(!canSave)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "Equipment")
            Text(editedClub == nil ? "New club." : "Edit club.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }

    // MARK: - Sections + fields

    private func section<Body: View>(_ title: String, @ViewBuilder content: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased())
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Rectangle().fill(palette.rule).frame(height: 1)
            }
            content()
        }
    }

    private func paperField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(AppFont.bodyLarge)
            .foregroundStyle(palette.ink)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private var kindMenu: some View {
        Menu {
            ForEach(ClubKind.allCases) { k in
                Button(k.displayName) { kind = k }
            }
        } label: {
            HStack {
                Text(kind.displayName)
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("›")
                    .font(AppFont.metadata)
                    .foregroundStyle(palette.ink2)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private var carryField: some View {
        HStack(spacing: 8) {
            TextField("yds", text: $yardsText)
                .font(AppFont.bodyLarge)
                .foregroundStyle(palette.ink)
                .keyboardType(.numberPad)
                .frame(width: 72)
            Text("yards")
                .font(AppFont.micro)
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
            Spacer()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func problemLines(_ list: [ClubValidation.Problem]) -> some View {
        ForEach(list.map(\.editorCopy), id: \.self) { line in
            problemText(line)
        }
    }

    private func problemText(_ line: String) -> some View {
        Text(line)
            .font(AppFont.micro)
            .tracking(0.8)
            .foregroundStyle(palette.red)
    }

    private func hint(_ copy: String) -> some View {
        Text(copy)
            .font(AppFont.micro)
            .tracking(0.8)
            .foregroundStyle(palette.ink3)
    }

    // MARK: - Delete (edit mode)

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("Delete club")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.red)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var deleteDialogTitle: String {
        "Delete \(editedClub?.name ?? "club")?"
    }

    /// Referenced clubs archive (Logbook keeps their names); unreferenced ones
    /// are gone for good — say which before the user commits.
    private var deleteDialogMessage: String {
        guard let club = editedClub else { return "" }
        let referenced = (try? ClubRepository.isReferencedByShots(id: club.id)) ?? false
        return referenced
            ? "Removed from your bag and hidden. Past rounds keep the name."
            : "This club will be deleted."
    }

    // MARK: - Actions

    private func save() {
        guard let yards = parsedYards, yards > 0 else { return }
        let t = ClubValidation.trimmed(name: name, shortName: shortName)
        var club: Club
        switch mode {
        case .edit(let existing):
            club = existing
        case .create:
            let all = (try? ClubRepository.all(includeArchived: true)) ?? []
            club = Club(
                id: UUID().uuidString,
                name: t.name,
                shortName: t.shortName,
                kind: kind,
                defaultYards: yards,
                sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1
            )
        }
        club.name = t.name
        club.shortName = t.shortName
        club.kind = kind
        club.defaultYards = yards
        do {
            try ClubRepository.save(club) // shortName unique index is the backstop
            ClubCatalog.shared.invalidate()
            onSaved(club)
        } catch {
            actionError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        guard let club = editedClub else { return }
        do {
            try ClubRepository.delete(id: club.id)
            ClubCatalog.shared.invalidate()
            onDeleted(club.id)
        } catch ClubRepositoryError.lastPutter {
            actionError = "Can't delete the last putter — the PUTT keys depend on it."
        } catch {
            actionError = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}

// MARK: - Problem → inline copy

extension ClubValidation.Problem {
    /// Short inline error line for the editor (pure; unit-tested).
    var editorCopy: String {
        switch self {
        case .nameEmpty: return "Name required"
        case .nameTooLong: return "Name too long (\(ClubValidation.maxNameLength) max)"
        case .shortNameEmpty: return "Short name required"
        case .shortNameTooLong: return "\(ClubValidation.maxShortNameLength) characters max"
        case .shortNameTaken(let by): return "Short name taken by \(by)"
        }
    }
}

#Preview("Create") {
    ClubEditorSheet(mode: .create, onSaved: { _ in }, onDeleted: { _ in }, onCancel: {})
}

#Preview("Edit") {
    ClubEditorSheet(mode: .edit(Club.seedCatalog[14]), onSaved: { _ in }, onDeleted: { _ in }, onCancel: {})
}
