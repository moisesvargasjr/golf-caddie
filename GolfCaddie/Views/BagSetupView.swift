import SwiftUI

/// Paper-styled bag editor. First-launch flow (when the bag is empty) shows
/// this with no Cancel button; reached from Settings later with Cancel.
struct BagSetupView: View {
    @State private var bag: [Club]
    @State private var saveError: String?
    @State private var isEditing = false
    /// Tap any club row → edit it; "New club…" → create. Club edits apply
    /// immediately; bag composition still only applies on Save (deliberate).
    @State private var editor: ClubEditorSheet.Mode?
    private let onSave: ([Club]) -> Void
    private let onCancel: (() -> Void)?

    @Environment(\.palette) private var palette

    init(initialBag: [Club], onCancel: (() -> Void)? = nil, onSave: @escaping ([Club]) -> Void) {
        // First launch (empty bag): seed the recommended 13 by resolving their
        // ids against the catalog, so any renames carry through.
        let seed: [Club]
        if initialBag.isEmpty {
            let all = (try? ClubRepository.all()) ?? []
            seed = ClubConfiguration.recommendedDefault.bag.compactMap { id in
                all.first { $0.id == id }
            }
        } else {
            seed = initialBag
        }
        _bag = State(initialValue: seed)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var availableClubs: [Club] {
        ((try? ClubRepository.all()) ?? []).filter { c in
            !bag.contains { $0.id == c.id }
        }
    }

    /// The PUTT keys (watch/phone) resolve against a bag putter-kind club —
    /// the bag must always carry one.
    private var bagHasPutter: Bool {
        bag.contains { $0.kind == .putter }
    }

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
                        section(title: "Your bag (\(bag.count) club\(bag.count == 1 ? "" : "s"))") {
                            currentBagList
                        }

                        section(title: "Add club") {
                            addClubList
                        }

                        Text(usgaFootnote)
                            .font(AppFont.micro)
                            .tracking(0.8)
                            .foregroundStyle(palette.ink3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 40)
                }

                if !bagHasPutter {
                    Text("Bag needs a putter — the PUTT keys depend on it")
                        .font(AppFont.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.red)
                        .padding(.horizontal, 24)
                }

                if let saveError {
                    Text(saveError)
                        .font(AppFont.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.red)
                        .padding(.horizontal, 24)
                }

                saveButton
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editor) { mode in
            ClubEditorSheet(
                mode: mode,
                onSaved: { saved in
                    // A rename/kind change must reflect in the bag copy too;
                    // availableClubs re-reads the repo on the next render.
                    if let idx = bag.firstIndex(where: { $0.id == saved.id }) {
                        bag[idx] = saved
                    }
                    editor = nil
                },
                onDeleted: { id in
                    bag.removeAll { $0.id == id }
                    editor = nil
                },
                onCancel: { editor = nil }
            )
        }
        .themedRoot()
    }

    /// Informational only — the 14-club cap is a competition rule, not an app
    /// limit (B33 lifted the hard cap).
    private var usgaFootnote: String {
        if bag.count > 14 {
            return "USGA rules allow up to 14 clubs in competition — you're carrying \(bag.count)."
        }
        return "USGA rules allow up to 14 clubs in competition."
    }

    // MARK: - Top

    private var navRow: some View {
        HStack {
            if let onCancel {
                Button {
                    onCancel()
                } label: {
                    Text("‹ CANCEL")
                        .font(AppFont.metadata)
                        .tracking(1.4)
                        .foregroundStyle(palette.ink)
                }
            } else {
                Spacer().frame(width: 1)
            }
            Spacer()
            Button {
                isEditing.toggle()
            } label: {
                Text(isEditing ? "DONE" : "EDIT")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Stamp(text: "Equipment")
            ItalicHeadline(
                lines: ["The", "Bag."],
                font: AppFont.masthead,
                color: palette.ink,
                tracking: -2,
                lineSpacing: -6
            )
            .padding(.top, 10)
        }
    }

    private func section<Body: View>(title: String, @ViewBuilder content: () -> Body) -> some View {
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

    private var currentBagList: some View {
        VStack(spacing: 0) {
            if bag.isEmpty {
                Text("Tap a club below to add it.")
                    .font(AppFont.bodyLarge)
                    .italic()
                    .foregroundStyle(palette.ink3)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(bag.enumerated()), id: \.element) { idx, club in
                    // The bag can't lose its only putter via the − button; the
                    // Save gate below is the backstop for editor-side changes.
                    let isLastPutter = club.kind == .putter
                        && bag.filter({ $0.kind == .putter }).count == 1
                    HStack(spacing: 12) {
                        Button {
                            editor = .edit(club)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.custom(AppFont.monoName, size: 11).weight(.bold))
                                    .foregroundStyle(palette.ink3)
                                    .tabularNumerals()
                                    .frame(width: 28, alignment: .leading)
                                Text(club.shortName)
                                    .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                                    .foregroundStyle(palette.ink2)
                                    .frame(width: 36, alignment: .leading)
                                Text(club.name)
                                    .font(AppFont.bodyLarge)
                                    .foregroundStyle(palette.ink)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isEditing {
                            Button(role: .destructive) {
                                bag.removeAll { $0.id == club.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(isLastPutter ? palette.ink3 : palette.flag)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLastPutter)
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
                }
            }
        }
    }

    private var addClubList: some View {
        VStack(spacing: 0) {
            ForEach(availableClubs, id: \.self) { club in
                HStack(spacing: 12) {
                    Button {
                        editor = .edit(club)
                    } label: {
                        HStack {
                            Text(club.shortName)
                                .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                                .foregroundStyle(palette.ink2)
                                .frame(width: 36, alignment: .leading)
                            Text(club.name)
                                .font(AppFont.bodyLarge)
                                .foregroundStyle(palette.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        bag.append(club)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(palette.flag)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            }

            newClubRow
        }
    }

    private var newClubRow: some View {
        Button {
            editor = .create
        } label: {
            HStack {
                Text("New club…")
                    .font(AppFont.bodyLarge)
                    .italic()
                    .foregroundStyle(palette.flag)
                Spacer()
                Text("›")
                    .font(AppFont.metadata)
                    .foregroundStyle(palette.ink2)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 6) {
                Text("Save")
                    .font(AppFont.cta)
                    .italic()
                    .fontWeight(.regular)
                    .foregroundStyle(palette.paper.opacity(0.85))
                Text("bag")
                    .font(AppFont.cta)
                    .foregroundStyle(palette.paper)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(bag.isEmpty || !bagHasPutter ? palette.ink3 : palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(bag.isEmpty || !bagHasPutter)
    }

    private func save() {
        do {
            try ClubConfigurationRepository.save(ClubConfiguration(bag: bag.map(\.id)))
            onSave(bag)
        } catch {
            saveError = "Couldn't save bag: \(error.localizedDescription)"
        }
    }
}

#Preview("Empty") {
    BagSetupView(initialBag: []) { _ in }
}

#Preview("Configured") {
    BagSetupView(initialBag: ClubConfiguration.recommendedDefault.bag.compactMap { id in
        Club.seedCatalog.first { $0.id == id }
    }) { _ in }
}
