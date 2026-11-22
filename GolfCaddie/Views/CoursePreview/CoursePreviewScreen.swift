import CoreLocation
import SwiftUI

/// Look through a course's holes without starting a round (Home → PREVIEW).
/// The same `HoleMap` the round uses: the whole course with a badge per hole,
/// tap a hole (or its chip) to glide in — tee → green, par, length, SI — and
/// ‹ › to page through the holes. COURSE glides back out. On a hole, tap the
/// map to plan a shot: the line bends at that spot with both distances (tap
/// the spot again to clear it). Read-only: no round, no rows, nothing saved.
struct CoursePreviewScreen: View {
    let course: CuratedCourse
    let holes: [CoursePreviewHole]
    var initialHole: Int? = nil
    /// In a round (the hole grid): the holes that can be played next. A hole
    /// in it shows PLAY HOLE n › in place of COURSE MAP; nil = Home's preview.
    var playable: Set<Int>? = nil
    var onPlay: (Int) -> Void = { _ in }
    var closeTitle = "‹ HOME"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue
    @State private var mapController = HoleMapController()
    /// nil = the whole course.
    @State private var viewedHole: Int?
    /// The shot preview's spot on the hole on screen.
    @State private var aim: CLLocationCoordinate2D?
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0

    private var units: Units { Units(rawValue: unitsRaw) ?? .yards }
    private var hole: CoursePreviewHole? { viewedHole.flatMap { n in holes.first { $0.number == n } } }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                map(size: proxy.size)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                        topHeight = $0
                    }
                    Spacer(minLength: 0)
                    bottomBar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        bottomHeight = $0
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(uiColor: HoleMapColors.ink).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier(CoursePreviewID.root)
        .onAppear {
            guard viewedHole == nil, let initialHole, holes.contains(where: { $0.number == initialHole }) else { return }
            mapController.selectHole(initialHole, animated: false)
            viewedHole = initialHole
            #if DEBUG
            aim = Self.debugAim(holes.first { $0.number == initialHole })
            #endif
        }
    }

    // MARK: Map

    private func map(size: CGSize) -> some View {
        let onCourse = viewedHole == nil
        // The map fills the window (it ignores the safe area), so the free
        // area is everything between the bottom of the top bar and the top of
        // the bottom bar, in window coordinates.
        let bottomEdge = size.height - bottomHeight - 8
        let free = CGRect(x: 0, y: topHeight + 8, width: size.width,
                          height: max(0, bottomEdge - topHeight - 8))
        return HoleMap(
            mode: onCourse ? .course : .hole,
            controller: mapController,
            holeID: viewedHole.map { CoursePreview.mapID(course: course.id, hole: $0) },
            tee: onCourse ? nil : hole?.tee?.coordinate,
            green: onCourse ? nil : hole?.green?.coordinate,
            courseHoles: CoursePreview.outlines(holes),
            unobstructedRect: free.height > 40 ? free : nil,
            plan: HoleMapPlan(aim: aim, units: units),
            onPlanAim: { aim = $0 },
            onSelectHole: open
        )
        .accessibilityIdentifier(CoursePreviewID.map)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Text(closeTitle)
                    .font(RoundFont.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 12)
                    .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeTitle == "‹ HOME" ? "Back to Home" : "Back to the round")
            .accessibilityIdentifier(CoursePreviewID.close)

            VStack(alignment: .leading, spacing: 1) {
                Text(course.name)
                    .font(RoundFont.serifItalic(16).weight(.bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                StampLabel(text: "PREVIEW · " + CoursePreview.courseCaption(holes, units: units), size: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .chromeBox()
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottomBar: some View {
        if let hole {
            holeBar(hole)
        } else {
            holeStrip
        }
    }

    private func holeBar(_ hole: CoursePreviewHole) -> some View {
        HStack(spacing: 0) {
            stepButton("‹", label: "Previous hole", id: CoursePreviewID.previous) {
                CoursePreview.previous(before: hole.number, in: holes).map(show)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(hole.number)")
                    .font(RoundFont.serif(24).weight(.bold))
                    .foregroundStyle(palette.ink)
                StampLabel(text: CoursePreview.caption(hole, units: units) + noAnchorsNote(hole), size: 9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                StampLabel(text: planText(hole), size: 9, color: aim == nil ? nil : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(CoursePreviewID.holeTitle)
            stepButton("›", label: "Next hole", id: CoursePreviewID.next) {
                CoursePreview.next(after: hole.number, in: holes).map(show)
            }
            if let playable {
                if playable.contains(hole.number) { playButton(hole.number) }
            } else {
                courseMapButton
            }
        }
        .padding(.vertical, 6)
        .chromeBox()
    }

    private func playButton(_ number: Int) -> some View {
        Button { onPlay(number) } label: {
            Text("PLAY \(number) ›")
                .font(RoundFont.mono(11).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(palette.paper)
                .padding(.horizontal, 12)
                .frame(minHeight: RoundChromeMetrics.minTap)
                .background(palette.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .accessibilityLabel("Play hole \(number)")
        .accessibilityIdentifier(CoursePreviewID.play)
    }

    private var courseMapButton: some View {
            Button(action: showCourse) {
                Text(CourseMapText.courseMapButton)
                    .font(RoundFont.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: RoundChromeMetrics.minTap)
                    .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityIdentifier(CoursePreviewID.courseMap)
    }

    /// "TEE → SPOT 212 · SPOT → PIN 187 YD", or how to plan one.
    private func planText(_ hole: CoursePreviewHole) -> String {
        guard hole.green != nil else { return "NO GREEN MAPPED" }
        guard let aim, let tee = hole.tee?.coordinate, let green = hole.green?.coordinate,
              let summary = ShotPlan.summary(legs: ShotPlan.legs(start: tee, aim: aim, green: green),
                                             units: units, fromYou: false) else {
            return "TAP THE MAP TO PLAN A SHOT"
        }
        return summary
    }

    private func noAnchorsNote(_ hole: CoursePreviewHole) -> String {
        hole.tee == nil && hole.green == nil ? " · NOT MAPPED" : ""
    }

    private func stepButton(_ glyph: String, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(RoundFont.serif(26).weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: RoundChromeMetrics.minTap, height: RoundChromeMetrics.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Every hole as a chip; a tap glides in.
    private var holeStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            StampLabel(text: holes.isEmpty ? "NO HOLES IN THIS COURSE" : "TAP A HOLE TO PREVIEW IT", size: 8)
                .padding(.horizontal, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(holes, id: \.number) { hole in
                        Button { open(hole.number) } label: { chip(hole) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hole \(hole.number), par \(hole.par.map(String.init) ?? "unknown")")
                            .accessibilityIdentifier(CoursePreviewID.chip(hole.number))
                    }
                }
            }
            .clipped()
        }
        .padding(6)
        .chromeBox()
    }

    private func chip(_ hole: CoursePreviewHole) -> some View {
        VStack(spacing: 1) {
            Text("\(hole.number)")
                .font(RoundFont.mono(11))
                .foregroundStyle(palette.ink)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule))
            Text("P\(hole.par.map(String.init) ?? "—")")
                .font(RoundFont.mono(9))
                .foregroundStyle(palette.ink2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(minWidth: RoundChromeMetrics.minTap, minHeight: RoundChromeMetrics.minTap)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: 1))
        .contentShape(Rectangle())
    }

    #if DEBUG
    /// `-DebugPlanAt 0.6`: a spot 60% of the way from tee to green, nudged
    /// 25 m right of the line (screenshots can't tap).
    private static func debugAim(_ hole: CoursePreviewHole?) -> CLLocationCoordinate2D? {
        let fraction = UserDefaults.standard.double(forKey: "DebugPlanAt")
        guard fraction > 0, let tee = hole?.tee, let green = hole?.green else { return nil }
        let lat = tee.lat + (green.lat - tee.lat) * fraction
        let lng = tee.lng + (green.lng - tee.lng) * fraction
        // Perpendicular, ~25 m.
        let dLat = green.lat - tee.lat, dLng = (green.lng - tee.lng) * cos(tee.lat * .pi / 180)
        let length = max(hypot(dLat, dLng), 1e-9)
        let metres = 25.0 / 111_320
        return CLLocationCoordinate2D(latitude: lat - dLng / length * metres,
                                      longitude: lng + dLat / length * metres / cos(tee.lat * .pi / 180))
    }
    #endif

    // MARK: Moves (camera glides on the one map)

    /// From the course: glide in to the hole.
    private func open(_ number: Int) {
        aim = nil
        mapController.selectHole(number)
        withAnimation(.easeInOut(duration: 0.35)) { viewedHole = number }
    }

    /// ‹ › between holes: the hole id changes and the map re-frames.
    private func show(_ number: Int) {
        aim = nil
        viewedHole = number
    }

    private func showCourse() {
        aim = nil
        mapController.showWholeCourse()
        withAnimation(.easeInOut(duration: 0.35)) { viewedHole = nil }
    }
}

enum CoursePreviewID {
    static let root = "coursePreview.root"
    static let map = "coursePreview.map"
    static let close = "coursePreview.close"
    static let previous = "coursePreview.previous"
    static let next = "coursePreview.next"
    static let holeTitle = "coursePreview.hole"
    static let courseMap = "coursePreview.courseMap"
    static let play = "coursePreview.play"
    static func chip(_ number: Int) -> String { "coursePreview.chip.\(number)" }
}
