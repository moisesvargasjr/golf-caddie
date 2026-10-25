import SwiftUI

// The unfolded Duo (canvas boards Main, Portrait, Book). The map runs behind
// everything; these draw only the chrome, in window coordinates (the screen
// ignores the safe area), from `insets` (24 pt edges, 36 pt corners).

/// Fully open, wide: hole title top-left; compass · hide · score · CARD · ···
/// bottom-left; the 340 pt command panel on the right with the club list
/// down its right edge.
struct OpenWideLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    static let panelWidth: CGFloat = 340
    static let railWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .topLeading) {
            HoleTitleBar(model: model, actions: actions, style: .inline(size: 26))
                .fixedSize()
                .reportsChromeFrame("title")
                .pinned(.topLeading, insets: insets)

            HStack(spacing: 6) {
                CompassChromeButton(model: model, actions: actions)
                HideControlsButton(actions: actions)
                if let score = model.roundScoreText {
                    RoundScoreChip(text: score).padding(.leading, 6)
                }
                CardButton(actions: actions)
                RoundOverflowMenu(model: model, actions: actions)
            }
            .fixedSize()
            .reportsChromeFrame("cluster")
            .pinned(.bottomLeading, insets: insets)

            CommandPanel(model: model, actions: actions,
                         columnStyle: PanelColumn.Style(card: .stacked(hero: 60)),
                         railWidth: Self.railWidth)
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity)
                .reportsChromeFrame("panel")
                .padding(insets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// Fully open, portrait: the same panel on the right, full height — split
/// into two boxes around the hinge band so nothing sits on the fold. The top
/// box holds the score row, the yardage, the shots and the club list; the
/// bottom box the questions, score entry and actions. Nothing across the
/// bottom.
struct OpenPortraitLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets
    let windowSize: CGSize

    static let panelWidth: CGFloat = 316
    static let railWidth: CGFloat = 80
    /// Gap between a box and the hinge keep-out band.
    static let hingeGap: CGFloat = 8

    var body: some View {
        let band = SafeChrome.hingeBandWidth / 2 + Self.hingeGap
        let upperHeight = max(0, windowSize.height / 2 - band - insets.top)
        let lowerHeight = max(0, windowSize.height - insets.bottom - (windowSize.height / 2 + band))
        ZStack(alignment: .topLeading) {
            HoleTitleBar(model: model, actions: actions, style: .stacked(size: 24))
                .fixedSize()
                .reportsChromeFrame("title")
                .pinned(.topLeading, insets: insets)

            VStack(spacing: 6) {
                CompassChromeButton(model: model, actions: actions)
                HideControlsButton(actions: actions)
            }
            .fixedSize()
            .reportsChromeFrame("cluster")
            .pinned(.bottomLeading, insets: insets)

            VStack(spacing: 0) {
                CommandPanel(model: model, actions: actions,
                             columnStyle: PanelColumn.Style(card: .stacked(hero: 68), spacing: 12),
                             parts: [.card, .list], railWidth: Self.railWidth) {
                    PanelHeaderRow(model: model, actions: actions)
                }
                .frame(height: upperHeight)
                .reportsChromeFrame("panelTop")
                Spacer(minLength: 0)
                CommandPanel(model: model, actions: actions,
                             columnStyle: PanelColumn.Style(spacing: 12, alignment: .bottom),
                             parts: [.ask, .bottom], showsRail: false)
                    .frame(height: lowerHeight)
                    .reportsChromeFrame("panelBottom")
            }
            .frame(width: Self.panelWidth)
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// Book pose: the hole on the left page; the command panel fills the right
/// page, starting 16 pt past the hinge band.
struct BookLayout: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets
    let windowSize: CGSize

    static let railWidth: CGFloat = 80
    static let pageGap: CGFloat = 16

    var body: some View {
        let panelLeading = windowSize.width / 2 + SafeChrome.hingeBandWidth / 2 + Self.pageGap
        ZStack(alignment: .topLeading) {
            HoleTitleBar(model: model, actions: actions, style: .stacked(size: 24))
                .fixedSize()
                .reportsChromeFrame("title")
                .pinned(.topLeading, insets: insets)

            VStack(spacing: 6) {
                CompassChromeButton(model: model, actions: actions)
                HideControlsButton(actions: actions)
            }
            .fixedSize()
            .reportsChromeFrame("cluster")
            .pinned(.bottomLeading, insets: insets)

            CommandPanel(model: model, actions: actions,
                         columnStyle: PanelColumn.Style(card: .inline(hero: 64), showsHint: true,
                                                        showsListTitle: true),
                         railWidth: Self.railWidth) {
                PanelHeaderRow(model: model, actions: actions)
            }
            .reportsChromeFrame("panel")
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .padding(.trailing, insets.trailing)
            .padding(.leading, panelLeading)
        }
    }
}

/// While the controls are hidden on the open Duo / iPhone landscape: just
/// "148 SHOW CONTROLS" bottom-left.
struct OpenHiddenChrome: View {
    let model: RoundPanelModel
    let actions: RoundPanelActions
    let insets: EdgeInsets

    var body: some View {
        ShowControlsPill(model: model, actions: actions, label: "SHOW CONTROLS")
            .fixedSize()
            .pinned(.bottomLeading, insets: insets)
    }
}

extension View {
    /// Pins a fixed-size control into a corner of the full-window chrome.
    func pinned(_ alignment: Alignment, insets: EdgeInsets) -> some View {
        padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
