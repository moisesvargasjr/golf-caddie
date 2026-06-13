"""Offline swing/shot detector.

Impact-led design (revised after the 2026-06-12 range test). The handoff doc
framed this as "swing arc THEN look for impact," but real range data showed
that gates poorly: at a range you never stop moving, so a low gyro threshold
merges whole sequences into one over-long region and the real swing gets
discarded. The ball-strike impact, by contrast, is a large, brief, DISCRETE
event (10–22 g high-passed vs <1 g for putts/noise) — a far stronger and more
separable signal than the arc. So we lead with it:

  1. Find discrete impact peaks — high-passed raw-accel maxima above a
     threshold, separated by a refractory gap so one strike = one detection.
  2. Gate each by a swing arc — require the smoothed gyro-magnitude envelope
     to exceed an arc threshold in the ~1 s leading into the impact. This
     rejects bag-drops / table-taps (impact, no swing) while surviving
     continuous between-shot motion (each impact is evaluated independently).

The residual error is physical, not algorithmic: a full-speed practice swing
that brushes the turf produces a ball-strike-like impact and cannot be
separated from a real shot by wrist motion alone (see the range-test readout).

Usage:
  python detect.py SESSION_DIR [--impact-thresh 4.0] [--arc-thresh 6.0] ...
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
    t_peak: float  # uptime of the impact spike
    peak_gyro: float  # rad/s, max gyro envelope in the swing-arc window
    impact_peak_g: float  # high-passed accel magnitude at the spike
    is_shot: bool  # True for every emitted detection (impact + arc both met)


@dataclass
class Params:
    impact_hp_hz: float = 20.0  # high-pass cutoff isolating the impact transient
    impact_thresh_g: float = 4.0  # spike threshold on the high-passed magnitude
    refractory_s: float = 0.6  # min spacing between impacts (one strike = one hit)
    arc_thresh: float = 6.0  # rad/s, required gyro envelope into the impact
    arc_pre_s: float = 1.0  # look this far before the impact for the swing arc
    arc_post_s: float = 0.2  # ...and this far after (release continues briefly)


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


def _impact_peaks(t: np.ndarray, hp: np.ndarray, thresh: float, refractory: float) -> list[int]:
    """Indices of impact spikes above `thresh`, keeping the largest within each
    refractory window so a single multi-sample strike yields one peak."""
    peaks: list[int] = []
    last_t = -np.inf
    for i in np.flatnonzero(hp >= thresh):
        if t[i] - last_t < refractory:
            if hp[i] > hp[peaks[-1]]:  # a bigger sample in the same strike
                peaks[-1] = i
            continue
        peaks.append(int(i))
        last_t = t[i]
    return peaks


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
    for i in _impact_peaks(ta, hp, p.impact_thresh_g, p.refractory_s):
        t = ta[i]
        w = (tg >= t - p.arc_pre_s) & (tg <= t + p.arc_post_s)
        peak_gyro = float(gmag[w].max()) if w.any() else 0.0
        if peak_gyro >= p.arc_thresh:  # impact backed by a swing arc
            out.append(Detection(t_peak=float(t), peak_gyro=peak_gyro, impact_peak_g=float(hp[i]), is_shot=True))
    return out


def add_param_args(ap: argparse.ArgumentParser) -> None:
    d = Params()
    ap.add_argument("--impact-thresh", type=float, default=d.impact_thresh_g)
    ap.add_argument("--impact-hp-hz", type=float, default=d.impact_hp_hz)
    ap.add_argument("--arc-thresh", type=float, default=d.arc_thresh)
    ap.add_argument("--refractory", type=float, default=d.refractory_s)


def params_from_args(args: argparse.Namespace) -> Params:
    return Params(
        impact_hp_hz=args.impact_hp_hz,
        impact_thresh_g=args.impact_thresh,
        refractory_s=args.refractory,
        arc_thresh=args.arc_thresh,
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("session", help="session directory")
    add_param_args(ap)
    args = ap.parse_args()
    session = spikelib.load_session(args.session)
    dets = detect(session, params_from_args(args))
    print(f"{len(dets)} shots detected")
    print(f"{'t_peak':>12} {'arc gyro rad/s':>14} {'impact g':>9}")
    for d in dets:
        print(f"{d.t_peak:12.2f} {d.peak_gyro:14.1f} {d.impact_peak_g:9.2f}")


if __name__ == "__main__":
    main()
