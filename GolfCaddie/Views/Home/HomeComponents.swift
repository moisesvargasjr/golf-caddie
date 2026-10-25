import SwiftUI

// Shared Home pieces, sized per the Home-Open / Home-Folded mockups. Each
// layout only arranges them.

/// Mono label used across Home ("COURSE", "START ON", stamps).
struct HomeMonoLabel: View {
    let text: String
    var size: CGFloat = 9
    var tracking: CGFloat = 0.8
    var color: Color?

    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.custom(AppFont.monoName, size: size).weight(.bold))
            .tracking(tracking)
            .foregroundStyle(color ?? palette.ink2)
    }
}

/// A dot and a mono label: the watch and G2 status.
struct HomeStatusDot: View {
    let label: String
    let dotColor: Color
    let style: HomeCopyStyle

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: style == .open ? 6 : 5) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            HomeMonoLabel(text: label, size: style == .open ? 10 : 9,
                          tracking: style == .open ? 1 : 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Watch status next to G2 (the mockups' "WATCH READY · G2 OFF").
struct HomeStatusIndicators: View {
    let watch: WatchLinkStatus
    let glassesEnabled: Bool
    let style: HomeCopyStyle

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            HomeStatusDot(label: watch.label(style: style),
                          dotColor: watch.isLive ? palette.ink : palette.ink3, style: style)
                .accessibilityLabel(watch.accessibilityLabel)
                .accessibilityIdentifier(HomeID.watchStatus)
            HomeStatusDot(label: glassesEnabled ? "G2 LINKED" : "G2 OFF",
                          dotColor: glassesEnabled ? palette.red : palette.ink3, style: style)
                .accessibilityLabel(glassesEnabled ? "G2 glasses linked" : "G2 glasses off")
                .accessibilityIdentifier(HomeID.glassesStatus)
        }
    }
}

/// 44 pt bordered gear → Settings.
struct HomeSettingsButton: View {
    @Binding var bag: [Club]

    @Environment(\.palette) private var palette

    var body: some View {
        NavigationLink {
            SettingsView(bag: $bag)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(width: SafeChrome.minTapTarget, height: SafeChrome.minTapTarget)
                .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(HomeID.settings)
    }
}

/// The player's name, boxed, → Profile (replaces the "CADDIE · NO. n"
/// stamp; the round count moved into the Logbook button).
struct HomeProfileButton: View {
    @AppStorage(PlayerProfile.nameKey) private var name = ""
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationLink {
            ProfileView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person")
                    .font(.system(size: 15, weight: .medium))
                HomeMonoLabel(text: PlayerProfile.buttonTitle(name: name), size: 11, tracking: 1,
                              color: palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(palette.ink)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(minHeight: SafeChrome.minTapTarget)
            .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlayerProfile.trimmed(name).isEmpty ? "Profile: add your name" : "Profile: \(name)")
        .accessibilityIdentifier(HomeID.profile)
    }
}

/// A boxed navigation row (Controls guide): title, optional sub-line, ›.
struct HomeNavBox: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = 48

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HomeMonoLabel(text: title, size: 11, tracking: 1, color: palette.ink)
                if let subtitle { HomeMonoLabel(text: subtitle, size: 9, tracking: 0.6) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("›")
                .font(.custom(AppFont.serifName, size: 20).weight(.bold))
                .foregroundStyle(palette.ink)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(palette.paper, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

/// "The Fairway / Logbook." masthead.
struct HomeMasthead: View {
    let style: HomeCopyStyle

    @Environment(\.palette) private var palette

    var body: some View {
        let size: CGFloat = style == .open ? 58 : 40
        VStack(alignment: .leading, spacing: style == .open ? -6 : -4) {
            Text("The Fairway")
            Text("Logbook.")
        }
        .font(.custom(AppFont.serifName, size: size).weight(.bold).italic())
        .tracking(style == .open ? -2 : -1.5)
        .foregroundStyle(palette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Hard-shadowed bordered card, the mockups' paper panel.
struct HomePanel<Content: View>: View {
    var padding: CGFloat = 12
    var shadowOffset: CGFloat = 3
    var backgroundOpacity: Double = 0.9
    @ViewBuilder var content: () -> Content

    @Environment(\.palette) private var palette

    var body: some View {
        content()
            .padding(padding)
            .background(palette.paper.opacity(backgroundOpacity), ignoresSafeAreaEdges: [])
            .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
            .compositingGroup()
            .shadow(color: palette.cardShadow.color, radius: 0, x: shadowOffset, y: shadowOffset)
    }
}

/// Last entry card: course, score, delta and the hole strip.
struct HomeLastEntryCard: View {
    let entry: HomeRoundEntry
    let style: HomeCopyStyle

    @Environment(\.palette) private var palette

    var body: some View {
        HomePanel(padding: style == .open ? 13 : 11) {
            VStack(alignment: .leading, spacing: style == .open ? 8 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    HomeMonoLabel(text: "LAST ENTRY · " + (style == .open ? entry.dateAndDurationText
                                                                            : entry.dateText), tracking: 1)
                    Spacer(minLength: 8)
                    HomeMonoLabel(text: "REVIEW ›", size: 10, tracking: 1, color: palette.ink)
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(entry.courseTitle)
                        .font(.custom(AppFont.serifName, size: style == .open ? 26 : 22).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("\(entry.score)")
                        .font(.custom(AppFont.serifName, size: style == .open ? 44 : 38).weight(.bold))
                        .tabularNumerals()
                    if let delta = entry.deltaText {
                        HomeMonoLabel(text: delta, size: style == .open ? 13 : 12, tracking: 0,
                                      color: palette.ink)
                    }
                }
                .foregroundStyle(palette.ink)
                if !entry.cells.isEmpty {
                    strip
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the round")
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(entry.cells, id: \.number) { cell in
                VStack(spacing: 1) {
                    if style == .open {
                        HomeMonoLabel(text: "\(cell.number)", size: 8, tracking: 0)
                    }
                    HomeScoreCell(cell: cell)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, style == .open ? 6 : 5)
        .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private var accessibilityText: String {
        var text = "Last entry, \(entry.courseTitle), \(entry.dateText), score \(entry.score)"
        if let delta = entry.deltaText { text += ", \(delta)" }
        return text
    }
}

/// One score in the strip: circled under par, boxed over.
struct HomeScoreCell: View {
    let cell: HomeHoleCell

    @Environment(\.palette) private var palette

    var body: some View {
        Text("\(cell.score)")
            .font(.custom(AppFont.monoName, size: 10).weight(.bold))
            .foregroundStyle(palette.ink)
            .tabularNumerals()
            .frame(width: 17, height: 17)
            .overlay {
                switch cell.shape {
                case .circle: Circle().stroke(palette.ink, lineWidth: 1)
                case .square: Rectangle().stroke(palette.ink, lineWidth: 1)
                case .plain: EmptyView()
                }
            }
    }
}

/// No finished rounds yet.
struct HomeEmptyEntry: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeMonoLabel(text: "NO ROUNDS YET", tracking: 1.4)
            Text("Begin your first round.")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(HomeID.noEntry)
    }
}

/// LOGBOOK · n ROUNDS ›, a boxed navigation row.
struct HomeLogbookLink: View {
    let bag: [Club]
    let roundCount: Int
    /// Title and count on one line (the open Duo's section header).
    var inline = false

    var body: some View {
        NavigationLink {
            RoundListView(bag: bag)
        } label: {
            if inline {
                HomeNavBox(title: "LOGBOOK · \(HomeViewModel.roundsText(roundCount))", minHeight: SafeChrome.minTapTarget)
                    .fixedSize()
            } else {
                HomeNavBox(title: "LOGBOOK", subtitle: HomeViewModel.roundsText(roundCount))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Logbook, \(HomeViewModel.roundsText(roundCount).lowercased())")
        .accessibilityIdentifier(HomeID.logbook)
    }
}
