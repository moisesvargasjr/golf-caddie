import CoreLocation
import SwiftUI

/// B7.3 — the end-of-hole "what we tracked" confirmation card (Path A).
///
/// Renders the reconstructed full/putt split for the just-played hole and
/// flags any strokes the GPS fix left us unsure about, so the golfer can
/// confirm at a glance ("looks right" = the sheet's Confirm) or jump to a
/// flagged shot below to fix its club / pin. Pure view over a
/// `HoleReconstruction`; the host `HoleReviewSheet` owns the editable shot
/// list and the confirm action.
struct HoleReconstructionCard: View {
    /// Path A (watch located each shot) vs Path B (phone-only — strokes placed
    /// from the GPS track). Only changes the wording: A reads "tracked / the GPS
    /// fix was loose", B reads "reconstructed / placed from a guess".
    enum Mode { case tracked, reconstructed }

    let reconstruction: HoleReconstruction
    var mode: Mode = .tracked
    /// When set, the low-confidence note becomes a button that opens the pin
    /// corrector. Nil (e.g. in previews) → the note is plain text.
    var onAdjustPins: (() -> Void)? = nil

    @Environment(\.palette) private var palette

    private var total: Int { reconstruction.shots.count }
    private var full: Int { reconstruction.fullShotCount }
    private var putts: Int { reconstruction.puttCount }
    private var lowConfidence: [ReconstructedShot] { reconstruction.lowConfidenceShots }

    var body: some View {
        PaperCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            VStack(alignment: .leading, spacing: 12) {
                Stamp(text: mode == .tracked ? "What we tracked" : "What we reconstructed")

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(total)")
                        .font(.custom(AppFont.serifName, size: 44).weight(.bold))
                        .tracking(-1.5)
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                    Text(total == 1 ? "shot" : "shots")
                        .font(.custom(AppFont.serifName, size: 20).italic())
                        .foregroundStyle(palette.ink2)
                    Spacer()
                    splitBadges
                }

                Rectangle().fill(palette.rule).frame(height: 1)

                if lowConfidence.isEmpty {
                    confirmLine
                } else {
                    lowConfidenceNote
                }
            }
        }
    }

    // The full/putt breakdown as ink stamps — putts stay muted (they cluster
    // on the green and don't need a precise location).
    private var splitBadges: some View {
        HStack(spacing: 6) {
            Stamp(text: "\(full) full")
            if putts > 0 {
                Stamp(text: "\(putts) putt\(putts == 1 ? "" : "s")", color: palette.ink2)
            }
        }
    }

    private var confirmLine: some View {
        Text(mode == .tracked
             ? "Looks complete — confirm below if it's right."
             : "Placed from your track — confirm, or nudge the pins below.")
            .font(AppFont.micro)
            .tracking(0.6)
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lowConfidenceNote: some View {
        if let onAdjustPins {
            Button(action: onAdjustPins) { noteBody(actionable: true) }
                .buttonStyle(.plain)
        } else {
            noteBody(actionable: false)
        }
    }

    private func noteBody(actionable: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Stamp(text: "Check \(lowConfidence.count)", color: palette.flag)
            Text(lowConfidenceCopy)
                .font(AppFont.micro)
                .tracking(0.3)
                .foregroundStyle(palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if actionable {
                Text("›")
                    .font(.custom(AppFont.serifName, size: 22).weight(.bold))
                    .foregroundStyle(palette.flag)
            }
        }
        .contentShape(Rectangle())
    }

    // "Shot III: the GPS fix was loose — adjust the pin to fix it."
    private var lowConfidenceCopy: String {
        let romans = lowConfidence
            .compactMap { reconstruction.shots.firstIndex(of: $0) }
            .map { ($0 + 1).roman }
        let list = romans.joined(separator: ", ")
        let plural = lowConfidence.count == 1
        let reason = mode == .tracked ? "the GPS fix was loose" : "we placed \(plural ? "it" : "them") from a guess"
        return "Shot\(plural ? "" : "s") \(list): \(reason) — "
            + "adjust the pin to fix \(plural ? "it" : "them")."
    }
}

// MARK: - Preview

#Preview("States") {
    func shot(_ seq: Int, club: ClubID?, acc: Double?, hadGPS: Bool = true) -> Shot {
        Shot(id: UUID(), holeID: UUID(), sequenceNumber: seq, timestamp: Date(),
             latitude: 34.0, longitude: -117.0, gpsAccuracy: acc, hadGPS: hadGPS,
             club: club, source: .watchAuto, notes: nil)
    }
    func recon(_ shots: [Shot], green: CLLocationCoordinate2D?) -> HoleReconstruction {
        Reconstructor.reconstruct(shots: shots, green: green,
                                  config: ReconstructionConfig(greenRadiusMeters: 25))
    }
    // Green far away so only the putter classifies as a putt in these mocks.
    let green = CLLocationCoordinate2D(latitude: 35.0, longitude: -118.0)

    return ScrollView {
        VStack(spacing: 20) {
            // Clean: 3 full + 2 putts, all tight fixes.
            HoleReconstructionCard(reconstruction: recon([
                shot(1, club: .driver, acc: 4), shot(2, club: .sevenIron, acc: 5),
                shot(3, club: .pitchingWedge, acc: 4), shot(4, club: .putter, acc: 6),
                shot(5, club: .putter, acc: 6),
            ], green: green))

            // One loose fix + one no-GPS shot → two flagged.
            HoleReconstructionCard(reconstruction: recon([
                shot(1, club: .driver, acc: 4), shot(2, club: .sevenIron, acc: 22),
                shot(3, club: .pitchingWedge, acc: nil, hadGPS: false), shot(4, club: .putter, acc: 6),
            ], green: green))

            // Single shot, ace-ish.
            HoleReconstructionCard(reconstruction: recon([
                shot(1, club: .sevenIron, acc: 5),
            ], green: green))
        }
        .padding(24)
    }
    .background(PaletteValues.light.paper)
    .environment(\.palette, .light)
}
