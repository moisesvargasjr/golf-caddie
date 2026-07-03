import SwiftUI

/// Paper-styled retro-link picker — pick a curated course for a round, or
/// unlink it. Empty-catalog state nudges to sync. Pull-to-refresh (B29)
/// force-syncs the catalog past the hourly throttle — a same-day published
/// course is one gesture away instead of an hour.
struct CoursePickerSheet: View {
    let courses: [CuratedCourse]
    let current: String?
    let onPick: (String?) -> Void
    let onCancel: () -> Void
    /// Force-sync + re-read; returns the fresh catalog. nil → not refreshable.
    /// Failures soft-fail upstream (the spinner just ends, old list stays).
    var onRefresh: (() async -> [CuratedCourse])? = nil

    @Environment(\.palette) private var palette
    /// The last pull's result; wins over the passed-in list once set (the
    /// parent's copy also refreshes, but this keeps the sheet correct even if
    /// the parent doesn't re-render mid-presentation).
    @State private var refreshedCourses: [CuratedCourse]? = nil

    private var displayedCourses: [CuratedCourse] { refreshedCourses ?? courses }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                navRow
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                courseList
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
    }

    @ViewBuilder
    private var courseList: some View {
        if let onRefresh {
            scrollBody.refreshable {
                refreshedCourses = await onRefresh()
            }
        } else {
            scrollBody
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if displayedCourses.isEmpty {
                    Text("No curated courses on this device yet. Pull down to refresh, or open the app online to sync.")
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(palette.ink3)
                        .padding(.top, 16)
                } else {
                    sectionHeader("Courses")
                    VStack(spacing: 0) {
                        ForEach(displayedCourses) { course in
                            courseRow(course)
                        }
                    }
                }

                if current != nil {
                    Button(role: .destructive) {
                        onPick(nil)
                    } label: {
                        HStack {
                            Stamp(text: "Unlink — no course", color: palette.flag)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
    }

    private var navRow: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Text("‹ CANCEL")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "Curated catalog")
            Text("Set course.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
            Spacer()
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }

    private func courseRow(_ course: CuratedCourse) -> some View {
        Button {
            onPick(course.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(palette.ink)
                    if let firstAlias = course.aliases.first {
                        Text(firstAlias.uppercased())
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.ink3)
                    }
                }
                Spacer()
                if course.id == current {
                    Stamp(text: "Linked", color: palette.flag)
                } else {
                    Text("›")
                        .font(AppFont.metadata)
                        .foregroundStyle(palette.ink2)
                }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}
