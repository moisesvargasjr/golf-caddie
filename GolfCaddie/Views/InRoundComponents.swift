import SwiftUI

// Building blocks for the expanded in-round layouts (command center A,
// tabletop C, wide). Each reads `InRoundSnapshot` and calls `InRoundActions`;
// none owns round state, so any arrangement can reuse them.

enum InRoundMetrics {
    /// Apple HIG minimum touch target.
    static let minTouch: CGFloat = 44
}

/// Grows a small control's hit area to >= 44 pt tall without changing its
/// drawn size or layout (compact stamps are ~22 pt tall). Mostly vertical, so
/// neighbouring stamps in a row don't steal each other's taps.
struct ExpandedHitShape: Shape {
    var minHeight: CGFloat = InRoundMetrics.minTouch
    var horizontal: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let dy = max(0, (minHeight - rect.height) / 2)
        return Path(rect.insetBy(dx: -horizontal, dy: -dy))
    }
}

extension View {
    /// See `ExpandedHitShape`.
    func minimumHitTarget() -> some View {
        contentShape(ExpandedHitShape())
    }
}

/// "Hole 7 · PAR 4 · 412 YD · COURSE · +2 THRU 6 · CARD · END"
struct InRoundHeaderBar: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HoleStepper(snapshot: snapshot, actions: actions)
                .fixedSize()
                .layoutPriority(2)
            VStack(alignment: .leading, spacing: 3) {
                // Drop the course name, then the length, when space is short.
                ViewThatFits(in: .horizontal) {
                    Stamp(text: holeStampText(includeCourse: true, includeLength: true))
                    Stamp(text: holeStampText(includeCourse: false, includeLength: true))
                    Stamp(text: holeStampText(includeCourse: false, includeLength: false))
                }
                if let score = snapshot.scoreText {
                    Text(score)
                        .font(AppFont.stamp).tracking(1.2)
                        .foregroundStyle(palette.flag)
                        .tabularNumerals()
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                HeaderStamp(text: "CARD", color: palette.ink, action: actions.openCard)
                HeaderStamp(text: "END", color: palette.flag, action: actions.endRound)
            }
            .fixedSize()
            .layoutPriority(2)
        }
    }

    private func holeStampText(includeCourse: Bool, includeLength: Bool) -> String {
        var parts = [snapshot.par.map { "PAR \($0)" } ?? "PAR —"]
        if includeLength, let length = snapshot.holeLengthText { parts.append(length) }
        if includeCourse, let course = snapshot.courseName { parts.append(course) }
        return parts.joined(separator: " · ")
    }
}

/// ‹ Hole N › — the numeral opens the hole grid.
struct HoleStepper: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            chevron("‹") { actions.stepHole(-1) }
            Button(action: actions.openHoleGrid) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Hole")
                        .font(.custom(AppFont.serifName, size: 15).italic())
                        .foregroundStyle(palette.ink2)
                    Text("\(snapshot.holeNumber)")
                        .font(.custom(AppFont.serifName, size: 34).weight(.bold))
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                }
                .frame(minHeight: InRoundMetrics.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hole \(snapshot.holeNumber), show all holes")
            chevron("›") { actions.stepHole(1) }
        }
    }

    private func chevron(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.custom(AppFont.serifName, size: 24).weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: InRoundMetrics.minTouch, height: InRoundMetrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(glyph == "‹" ? "Previous hole" : "Next hole")
    }
}

struct HeaderStamp: View {
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Stamp(text: text, color: color, size: .md)
                .frame(minWidth: InRoundMetrics.minTouch, minHeight: InRoundMetrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// TO PIN card: hero distance + FRONT / MIDDLE / BACK.
struct YardageCard: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    var heroSize: CGFloat = 76
    @Environment(\.palette) private var palette

    var body: some View {
        PaperCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(["TO PIN", snapshot.pinSourceText].compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.micro).tracking(1.4)
                    .foregroundStyle(palette.ink2)
                if let pin = snapshot.pin {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(pin.value)")
                            .font(.custom(AppFont.serifName, size: heroSize).weight(.bold))
                            .tracking(-2.5)
                            .foregroundStyle(palette.ink)
                            .tabularNumerals()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(pin.unit)
                            .font(.custom(AppFont.monoName, size: 14).weight(.bold))
                            .foregroundStyle(palette.ink2)
                    }
                    FrontMiddleBack(pin: pin)
                } else {
                    PinUnavailable(snapshot: snapshot, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FrontMiddleBack: View {
    let pin: InRoundPin
    var includeMiddle = true
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            column("FRONT", pin.front)
            if includeMiddle { column("MIDDLE", pin.value) }
            column("BACK", pin.back)
        }
    }

    private func column(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(AppFont.micro).tracking(1.2).foregroundStyle(palette.ink3)
            Text("\(value)").font(AppFont.monoNumeral).foregroundStyle(palette.ink).tabularNumerals()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Link course ›" (nothing linked) or "No anchor" — same recovery the
/// compact yardage card offers.
struct PinUnavailable: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        if snapshot.needsCourseLink {
            Button(action: actions.linkCourse) {
                HStack(spacing: 4) {
                    Stamp(text: "Link course", color: palette.flag)
                    Text("›").font(.custom(AppFont.serifName, size: 14).italic().weight(.bold))
                        .foregroundStyle(palette.flag)
                }
                .frame(minHeight: InRoundMetrics.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Stamp(text: "No anchor", color: palette.ink3)
        }
    }
}

/// "Club" header + Bag cell + an N-column grid of clubs in play.
struct ClubGridSection: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    var title = "Club"
    var columns = 4
    /// Tight 44 pt cells with the average inline (narrow rails).
    var compactCells = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(AppFont.sectionTitle).foregroundStyle(palette.ink)
                Spacer()
                Button(action: actions.openBag) {
                    Text(snapshot.bagText + " ›")
                        .font(AppFont.stamp).tracking(1.2)
                        .foregroundStyle(palette.ink2)
                        .frame(minHeight: InRoundMetrics.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clubs in play")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
                      spacing: 6) {
                ForEach(snapshot.clubs) { chip in
                    ClubGridCell(chip: chip, compact: compactCells) { actions.selectClub(chip.club) }
                }
            }
        }
    }
}

private struct ClubGridCell: View {
    let chip: InRoundClubChip
    var compact = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(chip.club.shortName)
                            .font(.custom(AppFont.serifName, size: 15).italic().weight(.bold))
                        if let avg = chip.avgText {
                            Text(avg).font(.custom(AppFont.monoName, size: 8).weight(.bold))
                                .opacity(0.75).tabularNumerals()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else {
                    VStack(spacing: 1) {
                        Text(chip.club.shortName)
                            .font(.custom(AppFont.serifName, size: 17).italic().weight(.bold))
                        Text(chip.avgText.map { "avg \($0)" } ?? " ")
                            .font(AppFont.micro)
                            .opacity(0.75)
                            .tabularNumerals()
                    }
                }
            }
            .foregroundStyle(chip.isSelected ? palette.paper : palette.ink)
            .frame(maxWidth: .infinity, minHeight: InRoundMetrics.minTouch)
            .background(chip.isSelected ? palette.ink : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
    }
}

/// "This hole" — number · club on the left, distance and source on the right.
struct StrokeListSection: View {
    let snapshot: InRoundSnapshot
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("This hole").font(AppFont.sectionTitle).foregroundStyle(palette.ink)
                Spacer()
                Text("SHOTS \(snapshot.shots) · PEN \(snapshot.penalties)")
                    .font(AppFont.stamp).tracking(1.2).foregroundStyle(palette.ink3)
                    .tabularNumerals()
            }
            if snapshot.strokes.isEmpty {
                Text("No shots yet.")
                    .font(.custom(AppFont.serifName, size: 15).italic())
                    .foregroundStyle(palette.ink3)
                    .padding(.vertical, 6)
            }
            ForEach(snapshot.strokes) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(line.number)")
                        .font(AppFont.monoNumeral).foregroundStyle(palette.ink3).tabularNumerals()
                        .frame(width: 22, alignment: .leading)
                    Text(line.clubName)
                        .font(.custom(AppFont.serifName, size: 17).italic().weight(.bold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    if let distance = line.distanceText {
                        Text(distance).font(AppFont.monoNumeral).foregroundStyle(palette.ink).tabularNumerals()
                    }
                    Text(line.sourceText).font(AppFont.micro).tracking(1.2).foregroundStyle(palette.ink3)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            }
        }
    }
}

/// GPS accuracy + FOLLOW recenter, floating on the map in expanded layouts.
struct MapStatusChrome: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperCard(padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10)) {
                HStack(spacing: 5) {
                    Circle().fill(snapshot.gpsColor).frame(width: 6, height: 6)
                    Text(snapshot.gpsText)
                        .font(AppFont.micro).tracking(1.2)
                        .foregroundStyle(palette.ink2).tabularNumerals()
                }
            }
            if !snapshot.isFollowingMap {
                Button(action: actions.recenterMap) {
                    PaperCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.system(size: 11, weight: .bold))
                            Text("FOLLOW").font(AppFont.stamp).tracking(1.2)
                        }
                        .foregroundStyle(palette.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Inline action error, shared by every expanded layout.
struct InRoundErrorText: View {
    let text: String?
    @Environment(\.palette) private var palette

    var body: some View {
        if let text {
            Text(text)
                .font(AppFont.micro).tracking(1.2)
                .foregroundStyle(palette.red)
                .multilineTextAlignment(.leading)
        }
    }
}
