#!/usr/bin/env python3
"""Watch-standalone spike, step 7: compare a watch GPS telemetry session against
the phone's round database (docs/WATCH_STANDALONE_SPIKE.md).

    scripts/compare-watch-track.py <telemetry-dir-or-zip> <rounds.sqlite> [--course <id>] [--round <id-prefix>]

Inputs are the two exports from the phone: Settings → Watch GPS Log (the zip
per watch session) and Settings → Backup (the SQLite). The course catalog is
read from the coursedata checkout next to this repo (or --catalog).

Reports: fix cadence + accuracy, watch-vs-phone track gap, per-shot yardage
agreement, first-shot distance to the tee point, putt distance to the green,
battery. Stdlib only. Never commit the inputs — they're a GPS trail.
"""
import argparse, bisect, csv, datetime as dt, json, math, os, sqlite3, statistics as st, sys, tempfile, zipfile

R = 6_371_000.0


def meters(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    x = (lo2 - lo1) * math.cos((la1 + la2) / 2)
    return R * math.hypot(x, la2 - la1)


def yards(m):
    return m / 0.9144


def ts(s):
    return dt.datetime.strptime(s[:23], "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=dt.timezone.utc).timestamp()


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def load_telemetry(path):
    if path.endswith(".zip"):
        tmp = tempfile.mkdtemp()
        zipfile.ZipFile(path).extractall(tmp)
        path = tmp
    for root, _, files in os.walk(path):
        if "fixes.csv" in files:
            fixes = list(csv.DictReader(open(os.path.join(root, "fixes.csv"))))
            session = json.load(open(os.path.join(root, "session.json"))) if "session.json" in files else {}
            return fixes, session
    sys.exit(f"no fixes.csv under {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("telemetry")
    ap.add_argument("sqlite")
    ap.add_argument("--course", help="curated course id (default: the round's)")
    ap.add_argument("--round", help="round id prefix (default: newest round overlapping the session)")
    ap.add_argument("--catalog", default=os.path.expanduser("~/source/golf-caddie-coursedata/data/courses.json"))
    a = ap.parse_args()

    fixes, session = load_telemetry(a.telemetry)
    w = [(float(r["fixTime"]), float(r["lat"]), float(r["lng"]), float(r["hAcc"])) for r in fixes]
    wt = [x[0] for x in w]
    t0, t1 = wt[0], wt[-1]

    db = sqlite3.connect(a.sqlite)
    q = "select id, courseName, curatedCourseId, startedAt, endedAt from round order by startedAt desc"
    rounds = db.execute(q).fetchall()
    if a.round:
        rounds = [r for r in rounds if r[0].startswith(a.round)]
    else:
        rounds = [r for r in rounds if ts(r[3]) <= t1 and (r[4] is None or ts(r[4]) >= t0)] or rounds[:1]
    rid, cname, cid, started, ended = rounds[0]
    cid = a.course or cid
    print(f"Round: {cname} ({cid})  {started} → {ended}")
    print(f"Watch session: {session.get('sessionId', '?')}  build {session.get('appBuild', '?')}  "
          f"{session.get('deviceModel', '?')} watchOS {session.get('systemVersion', '?')}")

    # --- fixes ---------------------------------------------------------------
    acc = [x[3] for x in w if x[3] > 0]
    gaps = [b - a for a, b in zip(wt, wt[1:])]
    print(f"\nFixes: {len(w)} over {(t1 - t0) / 60:.0f} min; cadence median {st.median(gaps):.1f}s, "
          f"max gap {max(gaps):.1f}s, gaps >5s: {sum(g > 5 for g in gaps)}, invalid: {len(w) - len(acc)}")
    print(f"hAcc: median {st.median(acc):.1f} m, p90 {pct(acc, .9):.1f}, max {max(acc):.1f}")

    # --- track gap ------------------------------------------------------------
    p = [(ts(t), la, lo, ac) for t, la, lo, ac in db.execute(
        "select timestamp, latitude, longitude, accuracy from tracePoint where roundID=? order by timestamp", (rid,))]
    g = []
    for t, la, lo, _ in p:
        i = bisect.bisect_left(wt, t)
        c = [w[j] for j in (i - 1, i) if 0 <= j < len(w)]
        if c:
            f = min(c, key=lambda x: abs(x[0] - t))
            if abs(f[0] - t) <= 1.5:
                g.append(meters((la, lo), (f[1], f[2])))
    if g:
        print(f"\nWatch vs phone track: {len(g)} paired of {len(p)} breadcrumbs; gap median {st.median(g):.1f} m, "
              f"p90 {pct(g, .9):.1f}, p95 {pct(g, .95):.1f}, max {max(g):.1f}   (pass: median ≤ 5 m)")
    else:
        print("\nNo phone breadcrumbs overlap the session (was a phone round running?)")

    # --- shots ----------------------------------------------------------------
    cat = json.load(open(a.catalog))
    course = next((c for c in cat["courses"] if c["id"] == cid), None)
    greens = tees = {}
    if course:
        greens = {h["number"]: (h["greenAnchor"]["lat"], h["greenAnchor"]["lng"]) for h in course["holes"] if h.get("greenAnchor")}
        tees = {h["number"]: (h["teeAnchor"]["lat"], h["teeAnchor"]["lng"]) for h in course["holes"] if h.get("teeAnchor")}
    else:
        print(f"\n(course {cid} not in catalog — skipping tee/green checks)")

    ydiff, teed = [], []
    print("\nhole | shots (putts) | 1st full → tee | putts → green | watch/phone yds at each full shot")
    for hn, hid in db.execute("select holeNumber, id from hole where roundID=? order by holeNumber", (rid,)):
        shots = db.execute("select timestamp, latitude, longitude, isPutt, source from shot "
                           "where holeID=? and excludedAt is null order by sequenceNumber", (hid,)).fetchall()
        full = [s for s in shots if not s[3] and s[1] is not None]
        putts = [s for s in shots if s[3] and s[1] is not None]
        d1 = meters((full[0][1], full[0][2]), tees[hn]) if full and hn in tees else None
        if d1 is not None:
            teed.append(d1)
        pg = st.median([meters((s[1], s[2]), greens[hn]) for s in putts]) if putts and hn in greens else None
        ys = []
        for s in full:
            if hn not in greens:
                break
            t = ts(s[0]); i = bisect.bisect_left(wt, t)
            if 0 < i < len(w) and abs(w[i][0] - t) < 3:
                f = w[i]
                wy, py = yards(meters((f[1], f[2]), greens[hn])), yards(meters((s[1], s[2]), greens[hn]))
                ydiff.append(abs(wy - py)); ys.append(f"{wy:.0f}/{py:.0f}")
        print(f"{hn:>4} | {len(shots):>2} ({sum(1 for s in shots if s[3])})      | "
              f"{f'{d1:5.1f} m' if d1 is not None else '    —  '} | {f'{pg:5.1f} m' if pg is not None else '   —  '} | {' '.join(ys)}")
    if ydiff:
        print(f"\nYardage |watch − phone| at shot time: median {st.median(ydiff):.1f} yd, p90 {pct(ydiff, .9):.1f}, "
              f"max {max(ydiff):.1f}   (pass: ≤ 3 yd)")
    if teed:
        print(f"First shot → tee point: median {st.median(teed):.1f} m, within 15 m: {sum(d <= 15 for d in teed)}/{len(teed)}")

    # --- battery --------------------------------------------------------------
    bs, be = session.get("batteryStart"), session.get("batteryEnd")
    if bs is not None and be is not None:
        print(f"\nBattery: {bs}% → {be}% ({bs - be}% over {(t1 - t0) / 3600:.1f} h)   (pass: ≤ 35% / 18 holes)")


if __name__ == "__main__":
    main()
