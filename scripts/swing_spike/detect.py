"""Offline swing/shot detector prototype.

Two-stage rule from the handoff doc (§8):
  1. swing candidate — smoothed gyro-magnitude envelope exceeds a threshold
     for an arc-like duration;
  2. impact — a high-passed raw-accelerometer spike near the moment of peak
     angular velocity. Full shot iff both; arc without spike = practice swing.

Usage:
  python detect.py SESSION_DIR [--gyro-thresh 3.0] [--impact-thresh 2.0] ...
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass

import numpy as np
from scipy.signal import butter, sosfiltfilt

import spikelib
from spikelib import Session, magnitude, median_rate_hz


@dataclass
class Detection:
    t_peak: float  # uptime of peak angular velocity
    t_start: float
    duration: float
    peak_gyro: float  # rad/s
    impact_peak_g: float  # high-passed accel magnitude near the peak
    is_shot: bool


@dataclass
class Params:
    gyro_thresh: float = 3.0  # rad/s, smoothed magnitude
    min_dur: float = 0.15  # s, arc duration bounds
    max_dur: float = 2.5
    merge_gap: float = 0.25  # s, join above-threshold regions closer than this
    impact_hp_hz: float = 20.0  # high-pass cutoff for the impact channel
    impact_thresh_g: float = 2.0  # spike threshold on high-passed magnitude
    impact_pre: float = 0.10  # s before peak angular velocity
    impact_post: float = 0.25  # s after (impact trails peak speed slightly)


def highpass_magnitude(arr: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """High-pass each raw-accel axis, return the magnitude — the impact channel."""
    fs = median_rate_hz(arr)
    nyq = fs / 2.0
    if not np.isfinite(fs) or cutoff_hz >= nyq * 0.95:
        raise ValueError(f"cutoff {cutoff_hz} Hz too high for stream at {fs:.1f} Hz")
    sos = butter(4, cutoff_hz / nyq, btype="high", output="sos")
    v = arr["v"].astype(np.float64)
    hp = sosfiltfilt(sos, v, axis=0)
    return np.linalg.norm(hp, axis=1)


def _smooth(x: np.ndarray, fs: float, win_s: float = 0.05) -> np.ndarray:
    n = max(3, int(round(win_s * fs)) | 1)
    return np.convolve(x, np.ones(n) / n, mode="same")


def _regions_above(t: np.ndarray, x: np.ndarray, thresh: float, merge_gap: float) -> list[tuple[int, int]]:
    above = x >= thresh
    if not above.any():
        return []
    edges = np.flatnonzero(np.diff(above.astype(np.int8)))
    starts = list(edges[~above[edges]] + 1)
    ends = list(edges[above[edges]] + 1)
    if above[0]:
        starts.insert(0, 0)
    if above[-1]:
        ends.append(len(x))
    merged: list[tuple[int, int]] = []
    for s, e in zip(starts, ends):
        if merged and t[s] - t[merged[-1][1] - 1] < merge_gap:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    return merged


def detect(session: Session, p: Params | None = None) -> list[Detection]:
    p = p or Params()
    gyro, accel = session.gyro, session.accel
    if len(gyro) < 10 or len(accel) < 10:
        return []
    fs = median_rate_hz(gyro)
    gmag = _smooth(magnitude(gyro), fs)
    tg = gyro["t"]
    hp = highpass_magnitude(accel, p.impact_hp_hz)
    ta = accel["t"]

    out: list[Detection] = []
    for s, e in _regions_above(tg, gmag, p.gyro_thresh, p.merge_gap):
        dur = float(tg[e - 1] - tg[s])
        if not (p.min_dur <= dur <= p.max_dur):
            continue
        i_peak = s + int(np.argmax(gmag[s:e]))
        t_peak = float(tg[i_peak])
        w = (ta >= t_peak - p.impact_pre) & (ta <= t_peak + p.impact_post)
        impact = float(hp[w].max()) if w.any() else 0.0
        out.append(
            Detection(
                t_peak=t_peak,
                t_start=float(tg[s]),
                duration=dur,
                peak_gyro=float(gmag[i_peak]),
                impact_peak_g=impact,
                is_shot=impact >= p.impact_thresh_g,
            )
        )
    return out


def add_param_args(ap: argparse.ArgumentParser) -> None:
    d = Params()
    ap.add_argument("--gyro-thresh", type=float, default=d.gyro_thresh)
    ap.add_argument("--min-dur", type=float, default=d.min_dur)
    ap.add_argument("--max-dur", type=float, default=d.max_dur)
    ap.add_argument("--impact-hp-hz", type=float, default=d.impact_hp_hz)
    ap.add_argument("--impact-thresh", type=float, default=d.impact_thresh_g)


def params_from_args(args: argparse.Namespace) -> Params:
    return Params(
        gyro_thresh=args.gyro_thresh,
        min_dur=args.min_dur,
        max_dur=args.max_dur,
        impact_hp_hz=args.impact_hp_hz,
        impact_thresh_g=args.impact_thresh,
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("session", help="session directory")
    add_param_args(ap)
    args = ap.parse_args()
    session = spikelib.load_session(args.session)
    dets = detect(session, params_from_args(args))
    print(f"{len(dets)} swing candidates ({sum(d.is_shot for d in dets)} classified as shots)")
    print(f"{'t_peak':>12} {'dur s':>6} {'gyro rad/s':>11} {'impact g':>9}  verdict")
    for d in dets:
        print(
            f"{d.t_peak:12.2f} {d.duration:6.2f} {d.peak_gyro:11.1f} {d.impact_peak_g:9.2f}  "
            + ("SHOT" if d.is_shot else "swing (no impact)")
        )


if __name__ == "__main__":
    main()
