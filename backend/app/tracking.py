"""Turns per-frame detections into stable incidents.

A violation only becomes an incident after it is seen on the same tracked
person for `min_frames` consecutive sampled frames. This removes one-frame
false positives and stops the same worker from producing a new alert on
every frame (repeated alerts are merged into one incident).
"""
from collections import defaultdict


class ViolationTracker:
    def __init__(self, min_frames=3):
        self.min_frames = min_frames
        self.streaks = defaultdict(int)          # (track_id, type) -> consecutive frames
        self.confirmed = defaultdict(set)        # track_id -> confirmed types
        self.seen_tracks = set()
        self.clean_tracks = set()                # tracks never confirmed in violation

    def update(self, persons):
        """Feed one frame. Returns {track_id: [newly confirmed types]}."""
        new = {}
        active = set()
        for p in persons:
            tid = p.track_id if p.track_id is not None else -(p.idx + 1)
            self.seen_tracks.add(tid)
            for t in p.violations:
                key = (tid, t)
                active.add(key)
                self.streaks[key] += 1
                if self.streaks[key] >= self.min_frames and t not in self.confirmed[tid]:
                    self.confirmed[tid].add(t)
                    new.setdefault(tid, []).append(t)
        for key in list(self.streaks):
            if key not in active:
                self.streaks[key] = 0
        return new

    def stats(self):
        violators = {t for t, s in self.confirmed.items() if s}
        return {
            "persons_tracked": len(self.seen_tracks),
            "persons_in_violation": len(violators),
            "persons_compliant": len(self.seen_tracks - violators),
        }
