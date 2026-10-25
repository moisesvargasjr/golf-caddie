import SwiftUI

/// What a host passes `RoundMapScreen` to give it the course pose (PR 8: a
/// finished round's MAP). The host owns the route; the screen owns the map.
struct RoundMapCourse {
    var content: CourseMapContent
    /// The whole course is on screen (`viewedHole` is then ignored).
    var isShowing: Bool
    /// A hole tapped on the course map: the host moves its route to the hole.
    var openHole: (Int) -> Void
    /// COURSE MAP in a hole's review: the host moves its route to the course.
    var showCourse: () -> Void
}

// The course pose of the one round map. The same `HoleMap` (and its
// `HoleMapController`) serves the course and every hole, so moving between
// them is a camera glide on one MKMapView, never a new screen:
//
// - tap a hole → `selectHole(n)` starts the glide in on the course map, then
//   the host's route turns the map into hole n's review (`.course` → `.hole`
//   re-frames, animated, into the room the review panel leaves);
// - Next hole › → the hole changes and the map glides along to it;
// - COURSE MAP → `showWholeCourse()` first (clears the selected hole), then
//   the host's route goes back to `.course` and the map glides out.
extension RoundMapScreen {
    var isShowingCourse: Bool { course?.isShowing ?? false }

    /// The map's mode: the course overview, the live hole or a fixed hole.
    var mapMode: HoleMapMode {
        if isShowingCourse { return .course }
        return isViewingLive ? .live : .hole
    }

    /// COURSE MAP shows in a hole's review when the host has a course map.
    var offersCourseMap: Bool { course != nil && !isShowingCourse }

    func openCourseHole(_ number: Int) {
        guard let course, course.isShowing, HoleScoring.holeRange.contains(number) else { return }
        mapController.selectHole(number)
        withAnimation(.easeInOut(duration: Self.poseAnimationSeconds)) {
            course.openHole(number)
        }
    }

    func glideOutToCourse() {
        guard let course, !course.isShowing else { return }
        question = nil
        selectedShotID = nil
        mapController.showWholeCourse()
        withAnimation(.easeInOut(duration: Self.poseAnimationSeconds)) {
            course.showCourse()
        }
    }

    /// The panel fades in / out while the camera glides.
    static var poseAnimationSeconds: Double { 0.35 }

    @ViewBuilder
    func courseChrome(_ course: RoundMapCourse, layout: RoundMapLayout, insets: EdgeInsets) -> some View {
        CourseMapChrome(content: course.content, style: CourseMapChromeStyle.resolve(layout), insets: insets,
                        onOpenHole: { number in openCourseHole(number) },
                        onCard: host.openCard)
            .transition(.opacity)
    }
}

/// COURSE MAP — in a hole's review opened from a finished round: glides the
/// same map back out to the whole course. `compact` = the map glyph alone
/// (folded and iPhone rows).
struct CourseMapButton: View {
    let actions: RoundPanelActions
    var frame: ChromeFrame = .box
    var compact = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: actions.openCourseMap) {
            HStack(spacing: 6) {
                Image(systemName: "map").font(.system(size: 14, weight: .semibold))
                if !compact {
                    Text(CourseMapText.courseMapButton).font(RoundFont.mono(10)).tracking(0.8)
                }
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
            .chromeFrame(frame)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Course map: every hole of this round")
        .accessibilityIdentifier(CourseMapAccessibilityID.courseMapButton)
    }
}
