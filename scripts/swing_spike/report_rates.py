"""Sanity report for a recorded spike session — run this FIRST on real data.

Answers the day-one questions: what rate does the Series 6 actually deliver,
how jittery is it, are there gaps (background throttling?), does the impact
clip the accelerometer range, and what did the battery do.

Usage:
  python report_rates.py SESSION_DIR
"""

from __future__ import annotations

import argparse

import numpy as np

import spikelib


def stream_report(name: str, arr: np.ndarray, gap_s: float = 0.1) -> None:
    print(f"\n== {name} ==")
    if len(arr) < 2:
        print(f"  only {len(arr)} samples")
        return
    t = arr["t"]
    dt = np.diff(t)
    dur = t[-1] - t[0]
    print(f"  samples: {len(arr):,}   duration: {dur / 60:.1f} min   mean rate: {len(arr) / dur:.1f} Hz")
    pct = np.percentile(dt * 1000, [1, 50, 99])
    print(f"  interval ms  p1/p50/p99: {pct[0]:.1f} / {pct[1]:.1f} / {pct[2]:.1f}   max: {dt.max() * 1000:.0f}")
    gaps = dt[dt > gap_s]
    print(f"  gaps >{gap_s * 1000:.0f} ms: {len(gaps)}" + (f"   (worst {gaps.max():.2f} s)" if len(gaps) else ""))
    hist, edges = np.histogram(1.0 / np.clip(dt, 1e-4, None), bins=[0, 25, 50, 75, 90, 110, 150, 1000])
    print("  instantaneous-rate histogram (Hz):")
    for h, lo, hi in zip(hist, edges[:-1], edges[1:]):
        if h:
            print(f"    {lo:>4.0f}–{hi:<4.0f}: {h:>8,}  {h / len(dt):.1%}")


def saturation_report(accel: np.ndarray) -> None:
    print("\n== accel saturation ==")
    v = np.abs(accel["v"].astype(np.float64))
    peak = v.max(axis=0)
    print(f"  per-axis |max| g: x={peak[0]:.1f}  y={peak[1]:.1f}  z={peak[2]:.1f}")
    # Typical exposed range is ±8 g on older watch hardware; pinned samples
    # near the max are a clipping signature (which is itself a usable feature).
    near = (v > 7.5).any(axis=1).sum()
    print(f"  samples with any axis >7.5 g: {near:,} ({near / max(len(accel), 1):.2%})")


def battery_report(meta: dict) -> None:
    samples = meta.get("battery", [])
    print(f"\n== battery ({len(samples)} samples) ==")
    if len(samples) >= 2:
        t0, t1 = samples[0], samples[-1]
        hours = (t1["uptime"] - t0["uptime"]) / 3600
        drop = (t0["level"] - t1["level"]) * 100
        print(f"  {t0['level']:.0%} -> {t1['level']:.0%} over {hours:.2f} h", end="")
        if hours > 0.05:
            print(f"   ({drop / hours:.1f} %/h -> ~{100 / max(drop / hours, 0.1):.1f} h runtime)")
        else:
            print()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("session", help="session directory")
    args = ap.parse_args()
    s = spikelib.load_session(args.session)
    print(f"session: {s.meta.get('sessionId')}   device: {s.meta.get('device')}")
    print(f"marks: {len(s.marks)}   anchors: {len(s.meta.get('anchors', []))}   gyro source: {s.meta.get('gyroSource', 'raw')}")
    counts = s.meta.get("counts", {})
    for name, arr in (("deviceMotion", s.dm), ("raw accel", s.accel), ("raw gyro", s.gyro)):
        stream_report(name, arr)
    declared = (counts.get("dm"), counts.get("accel"), counts.get("gyro"))
    actual = (len(s.dm), len(s.accel), len(s.gyro))
    if None not in declared and declared != actual:
        print(f"\nWARNING: session.json counts {declared} != file records {actual} (truncated transfer?)")
    saturation_report(s.accel)
    battery_report(s.meta)


if __name__ == "__main__":
    main()
