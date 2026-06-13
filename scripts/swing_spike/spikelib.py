"""Shared library for the swing-detector spike.

Parses session directories recorded by the GolfCaddieWatch logging app and
provides a synthetic-session generator for tests.

Binary formats (little-endian, fixed-size records, schemaVersion 1):
  dm.bin    : t f8 (CMLogItem boot-relative seconds), userAccel xyz f4 (g),
              rotationRate xyz f4 (rad/s), gravity xyz f4 (g),
              attitude quaternion wxyz f4                       -> 60 B/rec
  accel.bin : t f8, raw accel xyz f4 (g)                        -> 20 B/rec
  gyro.bin  : t f8, raw rotation rate xyz f4 (rad/s)            -> 20 B/rec

session.json carries wall-clock anchors, ground-truth marks, battery samples,
and per-stream record counts (see SessionMeta.swift on the watch side).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

DM_DTYPE = np.dtype(
    [
        ("t", "<f8"),
        ("ua", "<f4", (3,)),  # userAcceleration, g
        ("rr", "<f4", (3,)),  # rotationRate, rad/s
        ("g", "<f4", (3,)),  # gravity, g
        ("q", "<f4", (4,)),  # attitude quaternion w,x,y,z
    ]
)
VEC_DTYPE = np.dtype([("t", "<f8"), ("v", "<f4", (3,))])

LABELS = ("full_shot", "practice_swing", "chip", "putt", "noise")
# Labels where a real ball strike occurs (detector should fire).
SHOT_LABELS = ("full_shot", "chip", "putt")
# Labels the detector must NOT classify as shots.
NEGATIVE_LABELS = ("practice_swing", "noise")


@dataclass
class Session:
    path: Path
    meta: dict
    dm: np.ndarray
    accel: np.ndarray
    gyro: np.ndarray

    @property
    def marks(self) -> list[dict]:
        return self.meta.get("marks", [])

    def uptime_to_wallclock(self, t):
        """Map boot-relative seconds to unix epoch seconds via anchor pairs."""
        anchors = self.meta["anchors"]
        up = np.array([a["uptime"] for a in anchors])
        offset = np.array([a["wallClock"] - a["uptime"] for a in anchors])
        return np.asarray(t) + np.interp(np.asarray(t), up, offset)

    def rep_windows(self, pre: float = 12.0, post: float = 2.0) -> list[dict]:
        """One window per ground-truth mark. The mark is tapped AFTER the rep,
        so the rep's motion lives in [mark - pre, mark + post]."""
        return [
            {
                "label": m["label"],
                "repIndex": m["repIndex"],
                "t0": m["uptime"] - pre,
                "t1": m["uptime"] + post,
                "mark": m["uptime"],
            }
            for m in self.marks
        ]


def slice_stream(arr: np.ndarray, t0: float, t1: float) -> np.ndarray:
    return arr[(arr["t"] >= t0) & (arr["t"] <= t1)]


def magnitude(arr: np.ndarray, field: str = "v") -> np.ndarray:
    return np.linalg.norm(arr[field].astype(np.float64), axis=1)


def median_rate_hz(arr: np.ndarray) -> float:
    if len(arr) < 2:
        return float("nan")
    return float(1.0 / np.median(np.diff(arr["t"])))


def load_session(path: str | Path) -> Session:
    path = Path(path)
    meta = json.loads((path / "session.json").read_text())
    if meta.get("schemaVersion") != 1:
        raise ValueError(f"unsupported schemaVersion: {meta.get('schemaVersion')}")
    dm = np.fromfile(path / "dm.bin", dtype=DM_DTYPE)
    accel = np.fromfile(path / "accel.bin", dtype=VEC_DTYPE)
    gyro = np.fromfile(path / "gyro.bin", dtype=VEC_DTYPE)
    return Session(path=path, meta=meta, dm=dm, accel=accel, gyro=gyro)


def write_session(path: str | Path, meta: dict, dm: np.ndarray, accel: np.ndarray, gyro: np.ndarray) -> Path:
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    dm.astype(DM_DTYPE).tofile(path / "dm.bin")
    accel.astype(VEC_DTYPE).tofile(path / "accel.bin")
    gyro.astype(VEC_DTYPE).tofile(path / "gyro.bin")
    meta = dict(meta)
    meta.setdefault("schemaVersion", 1)
    meta["counts"] = {"dm": len(dm), "accel": len(accel), "gyro": len(gyro)}
    (path / "session.json").write_text(json.dumps(meta, indent=2))
    return path


# ---------------------------------------------------------------------------
# Synthetic sessions (tests + detector development before real data exists)
# ---------------------------------------------------------------------------

# (peak gyro rad/s, arc sigma s, impact peak g) per label; impact 0 = no strike.
# Magnitudes follow the 2026-06-12 range test: full shots and chips carry a
# large ball-strike transient; a practice swing has the arc but a small (here,
# clean — no turf) impact; putts/noise have neither.
_SYNTH_PROFILE = {
    "full_shot": (24.0, 0.15, 12.0),
    "practice_swing": (20.0, 0.15, 1.5),
    "chip": (10.0, 0.13, 8.0),
    "putt": (3.0, 0.20, 0.5),
    "noise": (3.0, 0.80, 0.3),
}


def make_synthetic_session(
    outdir: str | Path,
    reps: list[str] | None = None,
    rate_hz: float = 100.0,
    spacing_s: float = 20.0,
    seed: int = 0,
) -> Path:
    """Write a synthetic session directory. Reps are spaced `spacing_s` apart;
    the ground-truth mark lands 1.5 s after each rep's arc peak (mimicking the
    user tapping the watch after the swing)."""
    rng = np.random.default_rng(seed)
    reps = reps if reps is not None else ["full_shot"] * 3 + ["practice_swing"] * 3 + ["chip", "putt", "noise"]

    t_start = 1000.0  # arbitrary boot-relative origin
    duration = spacing_s * (len(reps) + 1)
    # Jittered, non-uniform delivery on purpose — mirrors real CMMotionManager.
    dts = np.clip(rng.normal(1.0 / rate_hz, 0.0005, int(duration * rate_hz)), 0.004, 0.02)
    t = t_start + np.cumsum(dts)

    gyro_v = rng.normal(0.0, 0.05, (len(t), 3))
    accel_v = rng.normal(0.0, 0.02, (len(t), 3))

    marks = []
    rep_counter: dict[str, int] = {}
    for i, label in enumerate(reps):
        peak_gyro, sigma, impact_g = _SYNTH_PROFILE[label]
        c = t_start + spacing_s * (i + 1)
        env = np.exp(-0.5 * ((t - c) / sigma) ** 2)
        axis = rng.normal(0, 1, 3)
        axis /= np.linalg.norm(axis)
        gyro_v += np.outer(env * peak_gyro, axis)
        # Swing also moves the wrist: moderate low-frequency accel with the arc.
        accel_v += np.outer(env * min(peak_gyro / 6.0, 2.0), axis[::-1])
        if impact_g > 0.0:
            # ~30 ms burst right after peak angular velocity. Alternate sign
            # per sample (a Nyquist-rate oscillation) so the transient reliably
            # survives the analysis high-pass regardless of sample phase.
            env = np.exp(-0.5 * ((t - (c + 0.02)) / 0.012) ** 2)
            alt = np.where(np.arange(len(t)) % 2 == 0, 1.0, -1.0)
            accel_v[:, 0] += env * alt * impact_g
        rep_counter[label] = rep_counter.get(label, 0) + 1
        mark_t = c + 1.5
        marks.append(
            {
                "label": label,
                "repIndex": rep_counter[label],
                "uptime": mark_t,
                "wallClock": 1.7e9 + mark_t,
            }
        )

    dm = np.zeros(len(t), dtype=DM_DTYPE)
    dm["t"] = t
    # Sensor fusion attenuates the impact transient: userAccel = smoothed accel.
    kernel = np.ones(5) / 5.0
    for k in range(3):
        dm["ua"][:, k] = np.convolve(accel_v[:, k], kernel, mode="same")
    dm["rr"] = gyro_v
    dm["g"] = np.tile([0.0, 0.0, -1.0], (len(t), 1))
    dm["q"] = np.tile([1.0, 0.0, 0.0, 0.0], (len(t), 1))

    accel = np.zeros(len(t), dtype=VEC_DTYPE)
    accel["t"] = t
    accel["v"] = accel_v
    gyro = np.zeros(len(t), dtype=VEC_DTYPE)
    gyro["t"] = t
    gyro["v"] = gyro_v

    meta = {
        "schemaVersion": 1,
        "sessionId": f"spike-synth-{seed}",
        "device": {"model": "synthetic", "systemVersion": "0"},
        "anchors": [
            {"uptime": float(t[0]), "wallClock": 1.7e9 + float(t[0])},
            {"uptime": float(t[-1]), "wallClock": 1.7e9 + float(t[-1])},
        ],
        "marks": marks,
        "battery": [{"uptime": float(t[0]), "level": 1.0}, {"uptime": float(t[-1]), "level": 0.97}],
    }
    return write_session(outdir, meta, dm, accel, gyro)
