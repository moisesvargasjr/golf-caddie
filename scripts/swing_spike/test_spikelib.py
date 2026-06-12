"""Synthetic-data round-trip + detector separation test."""

import numpy as np

import detect
import metrics
import spikelib


def test_synthetic_roundtrip_and_detector(tmp_path):
    reps = ["full_shot"] * 4 + ["practice_swing"] * 4 + ["chip"] * 2 + ["noise"] * 2
    path = spikelib.make_synthetic_session(tmp_path / "session", reps=reps, seed=7)
    s = spikelib.load_session(path)

    # Round-trip: counts in session.json match the binary files.
    assert s.meta["counts"] == {"dm": len(s.dm), "accel": len(s.accel), "gyro": len(s.gyro)}
    assert len(s.marks) == len(reps)
    assert len(s.dm) > 0 and s.dm.dtype == spikelib.DM_DTYPE

    # Clock mapping is consistent with the anchors.
    a0 = s.meta["anchors"][0]
    assert np.isclose(s.uptime_to_wallclock(a0["uptime"]), a0["wallClock"])

    # Detector separates synthetic shots from practice swings and noise.
    report = metrics.evaluate([s], detect.Params(), pre=12.0, post=2.0)
    pl = report["per_label"]
    assert pl["full_shot"]["shot_detected"] == pl["full_shot"]["reps"] == 4
    assert pl["chip"]["shot_detected"] == pl["chip"]["reps"] == 2
    assert pl["practice_swing"]["shot_detected"] == 0
    assert pl["noise"]["shot_detected"] == 0
    assert report["unmatched_shots"] == 0
