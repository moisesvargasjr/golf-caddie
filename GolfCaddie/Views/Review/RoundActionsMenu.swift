import SwiftUI

/// Which round-level actions ··· offers for a finished round (plan rule 12:
/// share, resume, course and delete live in ···). Moved out of the old
/// `RoundReviewView`, keeping its rules:
/// - Resume: only a finished round, only where the host can resume it (the
///   review pushed right after End round, as before), never over a live round.
/// - Delete: only a finished round, never while a round is live.
/// - Course and share: always.
struct RoundActionsAvailability: Equatable, Sendable {
    let canShare: Bool
    let canResume: Bool
    let canChangeCourse: Bool
    let canDelete: Bool
    let isCourseLinked: Bool
    /// "Course · Native Oaks ✓" or "Link course…".
    let courseTitle: String

    static func resolve(round: Round, canResumeHere: Bool, liveRoundActive: Bool,
                        linkedCourseName: String?) -> RoundActionsAvailability {
        let finished = round.endedAt != nil
        let linked = round.curatedCourseId != nil
        let courseTitle: String
        if linked {
            courseTitle = "Course · \(linkedCourseName ?? "linked") ✓"
        } else {
            courseTitle = "Link course…"
        }
        return RoundActionsAvailability(
            canShare: true,
            canResume: finished && canResumeHere && !liveRoundActive,
            canChangeCourse: true,
            canDelete: finished && !liveRoundActive,
            isCourseLinked: linked,
            courseTitle: courseTitle)
    }
}

/// What the menu's items do; the host (`FinishedRoundScreen`) owns the
/// sheets, the delete confirmation and the writes.
struct RoundActionHandlers {
    var share: () -> Void = {}
    var resume: () -> Void = {}
    var changeCourse: () -> Void = {}
    var unlinkCourse: () -> Void = {}
    var delete: () -> Void = {}
}

/// The ··· items for a finished round: THIS ROUND · Share round, Resume
/// round, Course · Name ✓, Delete round… (Review-* boards). Used inside a
/// `Menu`, so each item is a plain `Button`.
struct RoundActionsMenu: View {
    let availability: RoundActionsAvailability
    /// "NATIVE OAKS · OCT 23 · 79 (+7)" — the section header.
    var title = "THIS ROUND"
    let handlers: RoundActionHandlers
    /// + PENALTY on a layout that keeps it in ··· (nil: not offered).
    var addPenalty: (() -> Void)? = nil

    var body: some View {
        if let addPenalty {
            Button("Add a penalty…", action: addPenalty)
        }
        Section(title) {
            if availability.canShare {
                Button(action: handlers.share) { Label("Share round", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier(RoundActionsAccessibilityID.share)
            }
            if availability.canResume {
                Button(action: handlers.resume) { Label("Resume round", systemImage: "play") }
                    .accessibilityIdentifier(RoundActionsAccessibilityID.resume)
            }
            if availability.canChangeCourse {
                Button(action: handlers.changeCourse) { Label(availability.courseTitle, systemImage: "flag") }
                    .accessibilityIdentifier(RoundActionsAccessibilityID.course)
                if availability.isCourseLinked {
                    Button("Unlink course", role: .destructive, action: handlers.unlinkCourse)
                }
            }
            if availability.canDelete {
                Button(role: .destructive, action: handlers.delete) {
                    Label("Delete round…", systemImage: "trash")
                }
                .accessibilityIdentifier(RoundActionsAccessibilityID.delete)
            }
        }
    }
}

/// ··· on a finished round's card (Round-Open / Round-Folded boards): the
/// same round actions as the review's ···, in the card's ink.
struct CardRoundActionsButton: View {
    let availability: RoundActionsAvailability
    var title = "THIS ROUND"
    let handlers: RoundActionHandlers

    var body: some View {
        Menu {
            RoundActionsMenu(availability: availability, title: title, handlers: handlers)
        } label: {
            Text("···")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CardInk.ink)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(Rectangle().strokeBorder(CardInk.ink, lineWidth: CardInk.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Round options: share, resume, course, delete")
        .accessibilityIdentifier(RoundActionsAccessibilityID.cardMenu)
    }
}

enum RoundActionsAccessibilityID {
    static let cardMenu = "scorecard.roundActions"
    static let share = "round.actions.share"
    static let resume = "round.actions.resume"
    static let course = "round.actions.course"
    static let delete = "round.actions.delete"
}
