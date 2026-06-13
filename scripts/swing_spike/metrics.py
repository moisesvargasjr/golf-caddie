"""§9 decision-gate metrics: FP/FN rates from labeled spike sessions.

Matches detector output against ground-truth marks. A rep window spans
[mark - pre, mark + post]; a shot detection inside the window counts for that
rep. Positives = full_shot / chip / putt (FN reported per label); negatives =
practice_swing / noise (any shot detection is an FP).

Usage:
  python metrics.py SESSION_DIR [SESSION_DIR ...] [detector args]
"""

from __future__ import annotations

import argparse

import detect
import spikelib


def evaluate(sessions: list[spikelib.Session], params: detect.Params, pre: float, post: float) -> dict:
    """One-to-one match each detection to its single nearest mark.

    A mark is tapped just after its rep, so a detection (the impact) lands a
    little BEFORE its mark — eligible matches are detections in
    [mark - pre, mark + post]. Reps can be spaced closer than that window, so
    we assign greedily by smallest |detection - mark| distance, each detection
    claiming at most one mark and vice versa. This avoids the wide-window
    artifact where one real strike is double-counted into an adjacent rep.
    """
    per_label: dict[str, dict[str, int]] = {l: {"reps": 0, "shot_detected": 0} for l in spikelib.LABELS}
    unmatched_shots = 0
    for s in sessions:
        dets = [d for d in detect.detect(s, params) if d.is_shot]
        marks = s.marks
        for m in marks:
            per_label[m["label"]]["reps"] += 1

        # Candidate (mark, det) pairs within the eligibility window, sorted by
        # temporal distance; greedily commit the closest, one claim each.
        pairs = []
        for mi, m in enumerate(marks):
            for di, d in enumerate(dets):
                if m["uptime"] - pre <= d.t_peak <= m["uptime"] + post:
                    pairs.append((abs(d.t_peak - m["uptime"]), mi, di))
        pairs.sort()
        claimed_marks: set[int] = set()
        claimed_dets: set[int] = set()
        for _, mi, di in pairs:
            if mi in claimed_marks or di in claimed_dets:
                continue
            claimed_marks.add(mi)
            claimed_dets.add(di)
            per_label[marks[mi]["label"]]["shot_detected"] += 1
        unmatched_shots += len(dets) - len(claimed_dets)
    return {"per_label": per_label, "unmatched_shots": unmatched_shots}


def print_report(r: dict) -> None:
    pl = r["per_label"]
    print(f"{'label':<16} {'reps':>5} {'as shot':>8} {'rate':>7}")
    for label in spikelib.LABELS:
        row = pl[label]
        rate = row["shot_detected"] / row["reps"] if row["reps"] else float("nan")
        print(f"{label:<16} {row['reps']:>5} {row['shot_detected']:>8} {rate:>6.0%}")

    def agg(labels):
        reps = sum(pl[l]["reps"] for l in labels)
        det = sum(pl[l]["shot_detected"] for l in labels)
        return reps, det

    pos_reps, pos_det = agg(spikelib.SHOT_LABELS)
    neg_reps, neg_det = agg(spikelib.NEGATIVE_LABELS)
    print()
    if pos_reps:
        print(f"false-negative rate (all shot reps): {(pos_reps - pos_det) / pos_reps:.0%}")
        fr = pl["full_shot"]
        if fr["reps"]:
            print(f"  full shots only:                   {(fr['reps'] - fr['shot_detected']) / fr['reps']:.0%}")
    if neg_reps:
        print(f"false-positive rate (practice+noise): {neg_det / neg_reps:.0%}")
    print(f"shot detections outside any rep window: {r['unmatched_shots']}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sessions", nargs="+", help="session directories")
    # Mark is tapped just after the rep; the impact lands a few seconds before
    # it. Keep the window tight so closely-spaced reps don't cross-attribute.
    ap.add_argument("--window-pre", type=float, default=6.0, help="seconds before each mark")
    ap.add_argument("--window-post", type=float, default=1.5, help="seconds after each mark")
    detect.add_param_args(ap)
    args = ap.parse_args()
    sessions = [spikelib.load_session(p) for p in args.sessions]
    report = evaluate(sessions, detect.params_from_args(args), args.window_pre, args.window_post)
    print_report(report)


if __name__ == "__main__":
    main()
