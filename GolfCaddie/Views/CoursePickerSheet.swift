import SwiftUI

/// Paper-styled retro-link picker — pick a curated course for a round, or
/// unlink it. Empty-catalog state nudges to sync.
struct CoursePickerSheet: View {
    let courses: [CuratedCourse]
    let current: String?
    let onPick: (String?) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if courses.isEmpty {
                            Text("No curated courses on this device yet. Open the app online to sync.")
                                .font(AppFont.bodyLarge)
                                .italic()
                                .foregroundStyle(palette.ink3)
                                .padding(.top, 16)
                        } else {
                            sectionHeader("Courses")
                            VStack(spacing: 0) {
                                ForEach(courses) { course in
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
        }
        .presentationBackground(palette.paper)
        .themedRoot()
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
