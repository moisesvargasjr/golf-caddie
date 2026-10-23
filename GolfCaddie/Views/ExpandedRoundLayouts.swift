import SwiftUI

// The expanded in-round arrangements. Each is a set of role-tagged children
// for `AdaptiveRoundLayout` (header / panel / actions / page / map overlays).
// The map itself is NOT here — `ActiveRoundView` owns the single map instance
// and the layout moves it — so these can be swapped without touching map or
// round state.

/// Command center A — fully-open portrait (header, map left column, panel
/// right) and the book pose (map left page, everything else right page).
/// Both use the two-row bottom bar.
struct CommandCenterChrome: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions

    var body: some View {
        PaperBackground()
            .roundStageRole(.page)

        InRoundHeaderBar(snapshot: snapshot, actions: actions)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .roundStageRole(.header)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                YardageCard(snapshot: snapshot, actions: actions)
                ClubGridSection(snapshot: snapshot, actions: actions, columns: 4)
                StrokeListSection(snapshot: snapshot)
                InRoundErrorText(text: snapshot.errorText)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .roundStageRole(.panel)

        InRoundActionBar(snapshot: snapshot, actions: actions, showsWatchStatus: true)
            .roundStageRole(.actions)

        MapStatusChrome(snapshot: snapshot, actions: actions)
            .padding(.leading, 12)
            .padding(.top, 8)
            .padding(.trailing, RoundStageGeometry.hingeGutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .roundStageRole(.map)
    }
}

/// H4 — fully open, flat and wide. The hole map runs horizontally (tee left,
/// green right; `ActiveRoundMap.headingOffset = -90`) with the walked trail
/// and 200/150/100 rings; a ~300 pt rail on the right holds yardage, clubs,
/// strokes and the actions. Swap this body (and the `.wide` case of
/// `RoundStageGeometry.make`) to change the wide design in isolation.
struct WideRoundLayout: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions

    var body: some View {
        PaperBackground()
            .roundStageRole(.page)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                YardageCard(snapshot: snapshot, actions: actions, heroSize: 64)
                ClubGridSection(snapshot: snapshot, actions: actions, columns: 3)
                StrokeListSection(snapshot: snapshot)
                WatchDetectingLine(isDetecting: snapshot.watchDetecting)
                InRoundErrorText(text: snapshot.errorText)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .roundStageRole(.panel)

        InRoundActionBar(snapshot: snapshot, actions: actions, showsWatchStatus: false)
            .roundStageRole(.actions)

        WideMapOverlays(snapshot: snapshot, actions: actions)
            .roundStageRole(.map)
    }
}

/// H4 map overlays: hole/par card top-left (GPS + FOLLOW top-right),
/// score · CARD · END bottom-left.
private struct WideMapOverlays: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                PaperCard(padding: EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 12)) {
                    VStack(alignment: .leading, spacing: 0) {
                        HoleStepper(snapshot: snapshot, actions: actions)
                        Text(holeCaption)
                            .font(AppFont.micro).tracking(1.2)
                            .foregroundStyle(palette.ink2)
                            .padding(.leading, 12)
                    }
                }
                Spacer()
                MapStatusChrome(snapshot: snapshot, actions: actions)
            }
            Spacer()
            HStack(spacing: 8) {
                if let score = snapshot.scoreText {
                    PaperCard(padding: EdgeInsets(top: 13, leading: 12, bottom: 13, trailing: 12)) {
                        Text(score).font(AppFont.stampMd).tracking(1.2)
                            .foregroundStyle(palette.flag).tabularNumerals()
                    }
                }
                PaperCard(padding: 0) {
                    HStack(spacing: 0) {
                        HeaderStamp(text: "CARD", color: palette.ink, action: actions.openCard)
                            .padding(.horizontal, 6)
                        HeaderStamp(text: "END", color: palette.flag, action: actions.endRound)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
        .padding(12)
        // Keep the Apple Maps logo / Legal link (bottom-left) visible.
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var holeCaption: String {
        var parts = [snapshot.par.map { "PAR \($0)" } ?? "PAR —"]
        if let length = snapshot.holeLengthText { parts.append(length) }
        return parts.joined(separator: " · ")
    }
}

/// Tabletop C — half-folded with the hinge horizontal. Above the hinge: hole,
/// a huge yardage and FRONT/BACK (the shared map is the mini map on the
/// right). Below: club grid, big PUTT +1 beside a primary Finish hole, and the
/// small secondary row. Nothing sits on the hinge band.
struct TabletopChrome: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions

    var body: some View {
        PaperBackground()
            .roundStageRole(.page)

        TabletopUpperHalf(snapshot: snapshot, actions: actions)
            .roundStageRole(.header)

        TabletopLowerHalf(snapshot: snapshot, actions: actions)
            .roundStageRole(.panel)
    }
}

private struct TabletopUpperHalf: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HoleStepper(snapshot: snapshot, actions: actions)
                Stamp(text: snapshot.par.map { "PAR \($0)" } ?? "PAR —")
                if let score = snapshot.scoreText {
                    Text(score).font(AppFont.stamp).tracking(1.2).foregroundStyle(palette.flag)
                }
            }
            Text(["TO PIN", snapshot.pinSourceText].compactMap { $0 }.joined(separator: " · "))
                .font(AppFont.metadata).tracking(1.4)
                .foregroundStyle(palette.ink2)
            if let pin = snapshot.pin {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(pin.value)")
                        .font(.custom(AppFont.serifName, size: 160).weight(.bold))
                        .tracking(-6)
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(pin.unit)
                        .font(.custom(AppFont.monoName, size: 18).weight(.bold))
                        .foregroundStyle(palette.ink2)
                }
                FrontMiddleBack(pin: pin, includeMiddle: false)
                    .frame(maxWidth: 260, alignment: .leading)
            } else {
                PinUnavailable(snapshot: snapshot, actions: actions)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TabletopLowerHalf: View {
    let snapshot: InRoundSnapshot
    let actions: InRoundActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                ClubGridSection(snapshot: snapshot, actions: actions, title: "Next club", columns: 5)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                PuttButton(snapshot: snapshot, actions: actions, label: "PUTT +1", fontSize: 18)
                    .frame(width: 150)
                FinishHoleButton(actions: actions, fontSize: 24)
            }
            .frame(height: 88)
            HStack(spacing: 8) {
                WatchDetectingLine(isDetecting: snapshot.watchDetecting)
                SecondaryActionRow(snapshot: snapshot, actions: actions)
            }
            InRoundErrorText(text: snapshot.errorText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
