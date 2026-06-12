"""Per-rep trace plots — the eyeball tool for designing the detector.

Writes one PNG per ground-truth mark into SESSION_DIR/plots/: gyro magnitude
(swing arc), high-passed raw-accel magnitude (impact channel), and userAccel
magnitude, with the mark time and detector verdicts overlaid.

Usage:
  python plot_session.py SESSION_DIR [--window-pre 12] [--window-post 2]
"""

from __future__ import annotations

import argparse

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

import detect
import spikelib
from spikelib import magnitude, slice_stream


def plot_rep(session: spikelib.Session, window: dict, dets: list[detect.Detection], hp_hz: float, outdir) -> None:
    t0, t1 = window["t0"], window["t1"]
    gyro = slice_stream(session.gyro, t0, t1)
    accel = slice_stream(session.accel, t0, t1)
    dm = slice_stream(session.dm, t0, t1)
    if len(gyro) < 10 or len(accel) < 10:
        return

    fig, axes = plt.subplots(3, 1, figsize=(10, 7), sharex=True)
    axes[0].plot(gyro["t"] - t0, magnitude(gyro), lw=0.7)
    axes[0].set_ylabel("gyro |ω| rad/s")
    axes[1].plot(accel["t"] - t0, detect.highpass_magnitude(accel, hp_hz), lw=0.7, color="tab:red")
    axes[1].set_ylabel(f"|accel| >{hp_hz:.0f} Hz (g)")
    if len(dm) >= 10:
        axes[2].plot(dm["t"] - t0, magnitude(dm, "ua"), lw=0.7, color="tab:green")
    axes[2].set_ylabel("userAccel |a| g")
    axes[2].set_xlabel(f"seconds from window start (uptime {t0:.1f})")

    for ax in axes:
        ax.axvline(window["mark"] - t0, color="k", ls="--", lw=1, label="mark")
        for d in dets:
            if t0 <= d.t_peak <= t1:
                ax.axvline(d.t_peak - t0, color="tab:orange" if d.is_shot else "tab:gray", ls=":", lw=1)
    axes[0].set_title(f"{window['label']} #{window['repIndex']}  (dashed=mark, dotted=detection, orange=shot)")
    fig.tight_layout()
    fig.savefig(outdir / f"rep_{window['label']}_{window['repIndex']:02d}.png", dpi=120)
    plt.close(fig)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("session", help="session directory")
    ap.add_argument("--window-pre", type=float, default=12.0)
    ap.add_argument("--window-post", type=float, default=2.0)
    detect.add_param_args(ap)
    args = ap.parse_args()

    session = spikelib.load_session(args.session)
    params = detect.params_from_args(args)
    dets = detect.detect(session, params)
    outdir = session.path / "plots"
    outdir.mkdir(exist_ok=True)
    windows = session.rep_windows(pre=args.window_pre, post=args.window_post)
    for w in windows:
        plot_rep(session, w, dets, params.impact_hp_hz, outdir)
    print(f"wrote {len(windows)} plots to {outdir}")


if __name__ == "__main__":
    main()
