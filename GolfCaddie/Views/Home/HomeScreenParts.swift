import SwiftUI

/// What a Home layout shows, resolved by `HomeView`.
struct HomeContent {
    let snapshot: HomeData.Snapshot
    let bag: [Club]
    let inPlayCount: Int
    let watch: WatchLinkStatus
    let glassesEnabled: Bool
    let courseLabel: String
    let actionError: String?
    let loadError: String?

    var bagCount: Int { bag.count }
    var clubsText: String { HomeViewModel.clubsRowText(inPlay: inPlayCount, total: bagCount) }
}

/// What a Home layout can ask `HomeView` to do.
struct HomeActions {
    /// Open the clubs in play (inline bag panel when open wide, sheet otherwise).
    let openBag: () -> Void
    /// Edit the bag itself (Bag Setup).
    let editBag: () -> Void
    let pickCourse: () -> Void
    let begin: () -> Void
    /// Reload after a round is deleted from its review.
    let refresh: () -> Void
}

/// Pushes a finished round: its card, then a hole's review on the map
/// (`FinishedRoundScreen`).
struct HomeRoundLink<Label: View>: View {
    let round: Round
    let bag: [Club]
    let onDeleted: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            FinishedRoundScreen(round: round, bag: bag, onDeleted: onDeleted)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

/// Last entry (tappable) or the empty state.
struct HomeLastEntrySlot: View {
    let content: HomeContent
    let style: HomeCopyStyle
    let onDeleted: () -> Void

    var body: some View {
        if let entry = content.snapshot.lastEntry {
            HomeRoundLink(round: entry.round, bag: content.bag, onDeleted: onDeleted) {
                HomeLastEntryCard(entry: entry, style: style)
            }
            .accessibilityIdentifier(HomeID.lastEntry)
        } else {
            HomeEmptyEntry()
        }
    }
}

/// Red error line under the start controls.
struct HomeErrorLine: View {
    let message: String?

    @Environment(\.palette) private var palette

    var body: some View {
        if let message {
            Text(message)
                .font(AppFont.micro)
                .tracking(1.2)
                .foregroundStyle(palette.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(HomeID.error)
        }
    }
}

/// The Duo's hinge line, faint and dashed, as the open mockup draws it.
struct HomeHingeLine: View {
    let windowSize: CGSize

    @Environment(\.palette) private var palette

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: windowSize.width / 2, y: 0))
            path.addLine(to: CGPoint(x: windowSize.width / 2, y: windowSize.height))
        }
        .stroke(palette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Profile (Profile-Folded): the player's name for the card's PLAYER line,
/// and an optional home course and handicap index. Save writes them.
struct ProfileView: View {
    @AppStorage(PlayerProfile.nameKey) private var storedName = ""
    @AppStorage(PlayerProfile.homeCourseKey) private var storedCourseId = ""
    @AppStorage(PlayerProfile.handicapKey) private var storedHandicap = ""
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var courseId = ""
    @State private var handicap = ""
    @State private var courses: [CuratedCourse] = []
    @State private var pickingCourse = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The player.")
                        .font(.custom(AppFont.serifName, size: 38).weight(.bold).italic())
                        .tracking(-1)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your name goes on the PLAYER line of every card.")
                        .font(.custom(AppFont.serifName, size: 14).italic())
                        .foregroundStyle(palette.ink2)
                }
                field("NAME") {
                    TextField("", text: $name, prompt: Text("Your name"))
                        .textContentType(.name)
                        .submitLabel(.done)
                        .accessibilityLabel("Name")
                        .accessibilityIdentifier("profile.name")
                }
                field("HOME COURSE", optional: true) {
                    Button { pickingCourse = true } label: {
                        HStack {
                            Text(courseName ?? "None")
                                .foregroundStyle(courseName == nil ? palette.ink2 : palette.ink)
                            Spacer()
                            Text("›").font(.custom(AppFont.serifName, size: 20).weight(.bold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Home course: \(courseName ?? "none"). Change")
                }
                VStack(alignment: .leading, spacing: 6) {
                    field("HANDICAP INDEX", optional: true) {
                        TextField("", text: $handicap, prompt: Text("e.g. 12.4"))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Handicap index")
                    }
                    HomeMonoLabel(text: handicapNote, size: 9, tracking: 0.6,
                                  color: handicapIsValid ? nil : palette.red)
                }
                cardPreview
                PrimaryActionButton(title: "Save", fontSize: 20, minHeight: 56, action: save)
                    .disabled(!handicapIsValid)
                    .opacity(handicapIsValid ? 1 : 0.4)
                    .accessibilityIdentifier("profile.save")
            }
            .foregroundStyle(palette.ink)
            .padding(SafeChrome.edgeInset)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.paper.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingCourse) {
            CoursePickerSheet(courses: courses, current: courseId.isEmpty ? nil : courseId,
                              onPick: { id in
                                  courseId = id ?? ""
                                  pickingCourse = false
                              },
                              onCancel: { pickingCourse = false })
        }
        .task {
            guard !loaded else { return }
            loaded = true
            name = storedName
            courseId = storedCourseId
            handicap = storedHandicap
            courses = await CourseDataRepository.allCoursesFromAsyncContext()
        }
        .accessibilityIdentifier("profile.screen")
    }

    private var courseName: String? {
        courseId.isEmpty ? nil : (courses.first { $0.id == courseId }?.name ?? "Linked course")
    }

    private var handicapIsValid: Bool {
        PlayerProfile.trimmed(handicap).isEmpty || PlayerProfile.handicapIndex(handicap) != nil
    }

    private var handicapNote: String {
        handicapIsValid ? "ONLY COMPLETE 18-HOLE ROUNDS WOULD COUNT TOWARD IT"
                        : "A HANDICAP INDEX RUNS FROM +10.0 TO 54.0"
    }

    /// The card's DATE / PLAYER lines, as they'll print.
    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeMonoLabel(text: "ON THE CARD", size: 9, tracking: 1)
            HStack(alignment: .bottom, spacing: 16) {
                handLine("DATE", Date().formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits)))
                handLine("PLAYER", PlayerProfile.trimmed(name))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private func handLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HomeMonoLabel(text: label, size: 10, tracking: 0)
            Text(value.isEmpty ? " " : value)
                .font(CardInk.hand(22))
                .foregroundStyle(CardInk.graphite)
                .frame(minWidth: 84, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: 1) }
        }
    }

    private func field<Content: View>(_ label: String, optional: Bool = false,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HomeMonoLabel(text: label, size: 10, tracking: 1, color: palette.ink)
                Spacer()
                if optional { HomeMonoLabel(text: "OPTIONAL", size: 10, tracking: 1) }
            }
            content()
                .font(.custom(AppFont.serifName, size: 20))
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
        }
    }

    private func save() {
        storedName = PlayerProfile.trimmed(name)
        storedCourseId = courseId
        storedHandicap = PlayerProfile.trimmed(handicap)
        dismiss()
    }
}
