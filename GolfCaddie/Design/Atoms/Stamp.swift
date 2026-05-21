import SwiftUI

/// Ink-stamped rectangular badge — the most-repeated atom in the design.
/// Used for status labels ("CONFIRMED", "+37"), section markers
/// ("CADDIE · NO. 247", "VOL. III · 2026"), and pill labels throughout.
///
/// Defaults to ink color; pass `color: palette.red` for the red "TRIPLE BOGEY" /
/// "+37" variant.
struct Stamp: View {
    enum Size { case sm, md }

    let text: String
    var color: Color? = nil
    var size: Size = .sm

    @Environment(\.palette) private var palette

    var body: some View {
        let strokeColor = color ?? palette.ink
        Text(text.uppercased())
            .font(size == .sm ? AppFont.stamp : AppFont.stampMd)
            .tracking(size == .sm ? 1.2 : 1.4)
            .foregroundStyle(strokeColor)
            .padding(.horizontal, size == .sm ? 8 : 10)
            .padding(.vertical, size == .sm ? 3 : 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(strokeColor, lineWidth: 1.2)
            )
            .fixedSize()
    }
}

#Preview("Light") {
    VStack(spacing: 12) {
        Stamp(text: "Caddie · No. 247")
        Stamp(text: "+37", color: PaletteValues.light.red)
        Stamp(text: "Official Card · No. 247", color: PaletteValues.light.red, size: .md)
        Stamp(text: "Confirmed")
    }
    .padding(40)
    .background(PaletteValues.light.paper)
    .environment(\.palette, .light)
}

#Preview("Dark") {
    VStack(spacing: 12) {
        Stamp(text: "Caddie · No. 247")
        Stamp(text: "+37", color: PaletteValues.dark.red)
        Stamp(text: "Vol. III · 2026", size: .md)
    }
    .padding(40)
    .background(PaletteValues.dark.paper)
    .environment(\.palette, .dark)
}
