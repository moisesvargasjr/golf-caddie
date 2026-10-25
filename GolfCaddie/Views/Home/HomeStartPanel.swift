import SwiftUI

/// "Start a round": Track shots / Casual, the Course row, the starting hole,
/// (folded) the clubs in play, and Begin. Stateless — the state is a
/// `HomeStartState` binding replaced with new copies.
struct HomeStartPanel: View {
    @Binding var state: HomeStartState
    let style: HomeCopyStyle
    let courseLabel: String
    let clubsText: String
    let beginSubtitle: String
    let onCourse: () -> Void
    let onClubs: () -> Void
    let onBegin: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HomePanel(padding: style == .open ? 14 : 12, shadowOffset: 4, backgroundOpacity: 0.96) {
            VStack(alignment: .leading, spacing: style == .open ? 10 : 8) {
                if style == .open {
                    Text("Start a round")
                        .font(.custom(AppFont.serifName, size: 22).weight(.bold).italic())
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                modePicker
                if style == .open {
                    HStack(spacing: 8) {
                        courseRow(minHeight: 48, labelSize: 9, valueSize: 14)
                        holeStepper(label: "START ON", minHeight: 48)
                    }
                } else {
                    courseRow(minHeight: SafeChrome.minTapTarget, labelSize: 10, valueSize: 15)
                    HStack(spacing: 8) {
                        holeStepper(label: "HOLE", minHeight: SafeChrome.minTapTarget)
                        clubsCell
                    }
                }
                beginButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HomeID.startPanel)
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.tracking, id: HomeID.modeTracking)
            modeButton(.casual, id: HomeID.modeCasual)
        }
        .overlay(Rectangle().stroke(palette.ink, lineWidth: 1.5))
    }

    private func modeButton(_ mode: RoundStartMode, id: String) -> some View {
        let selected = state.mode == mode
        return Button {
            state = state.with(mode: mode)
        } label: {
            VStack(spacing: 2) {
                Text(mode.title)
                    .font(.custom(AppFont.serifName, size: 15))
                Text(mode.caption)
                    .font(.custom(AppFont.monoName, size: style == .open ? 9 : 8).weight(.bold))
                    .tracking(0.6)
            }
            .foregroundStyle(selected ? palette.paper : palette.ink)
            .frame(maxWidth: .infinity, minHeight: style == .open ? 56 : 52)
            .background(selected ? palette.ink : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title): \(mode.caption.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: Course, hole, clubs

    private func courseRow(minHeight: CGFloat, labelSize: CGFloat, valueSize: CGFloat) -> some View {
        Button(action: onCourse) {
            HStack {
                HomeMonoLabel(text: "COURSE", size: labelSize)
                Spacer(minLength: 6)
                Text("\(courseLabel) ›")
                    .font(.custom(AppFont.serifName, size: valueSize))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .overlay(Rectangle().stroke(palette.ruleStrong, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Course: \(courseLabel)")
        .accessibilityHint("Pick the course")
        .accessibilityIdentifier(HomeID.course)
    }

    private func holeStepper(label: String, minHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            HomeMonoLabel(text: label)
            Spacer(minLength: 4)
            stepButton("‹", delta: -1, label: "Earlier starting hole", id: HomeID.holeDown)
            Text("\(state.startingHole)")
                .font(.custom(AppFont.serifName, size: 19).weight(.bold))
                .foregroundStyle(palette.ink)
                .tabularNumerals()
                .frame(width: 24)
                .accessibilityLabel("Starting hole \(state.startingHole)")
                .accessibilityIdentifier(HomeID.startingHole)
            stepButton("›", delta: 1, label: "Later starting hole", id: HomeID.holeUp)
        }
        .padding(.leading, style == .open ? 12 : 10)
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .overlay(Rectangle().stroke(palette.ruleStrong, lineWidth: 1.5))
    }

    private func stepButton(_ glyph: String, delta: Int, label: String, id: String) -> some View {
        Button {
            state = state.steppingHole(by: delta)
        } label: {
            Text(glyph)
                .font(.custom(AppFont.serifName, size: 20).weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: 40, height: SafeChrome.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var clubsCell: some View {
        if state.showsClubsRow {
            Button(action: onClubs) {
                HStack {
                    HomeMonoLabel(text: "CLUBS")
                    Spacer(minLength: 4)
                    Text("\(clubsText) ›")
                        .font(.custom(AppFont.serifName, size: 14))
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: SafeChrome.minTapTarget)
                .overlay(Rectangle().stroke(palette.ruleStrong, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clubs in play: \(clubsText)")
            .accessibilityIdentifier(HomeID.clubs)
        } else {
            HomeMonoLabel(text: "NO CLUBS NEEDED")
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: SafeChrome.minTapTarget, alignment: .leading)
        }
    }

    // MARK: Begin

    private var beginButton: some View {
        Button(action: onBegin) {
            VStack(spacing: 2) {
                Text("Begin")
                    .font(.custom(AppFont.serifName, size: 24).weight(.bold).italic())
                Text(beginSubtitle)
                    .font(AppFont.micro)
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(palette.paper)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(palette.ink)
            .compositingGroup()
            .shadow(color: palette.cardShadow.color, radius: 0, x: 3, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Begin round")
        .accessibilityValue(beginSubtitle.lowercased())
        .accessibilityIdentifier(HomeID.begin)
    }
}
