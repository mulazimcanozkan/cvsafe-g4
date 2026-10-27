"""Site safety KPIs computed from stored scans and incidents."""
import time
from collections import Counter

from .rules import VIOLATIONS

RANGES = {"today": 86400, "week": 7 * 86400, "month": 30 * 86400}


def _grade(score):
    if score >= 90:
        return "A", "Low Risk"
    if score >= 80:
        return "B", "Moderate Risk"
    if score >= 70:
        return "C", "Elevated Risk"
    return "D", "High Risk"


def _period(store, start, end, subs):
    scans = store.query("SELECT * FROM scans WHERE ts>=? AND ts<?", (start, end))
    incs = store.query("SELECT * FROM incidents WHERE created_at>=? AND created_at<?", (start, end))
    persons = sum(s["persons"] for s in scans)
    compliant = sum(s["compliant"] for s in scans)
    ppe_ok = sum(s["ppe_ok"] for s in scans)
    return scans, incs, persons, compliant, ppe_ok


def compute(store, cfg, rng="today"):
    import json
    span = RANGES.get(rng, RANGES["today"])
    now = time.time()
    subs = {s["id"]: s for s in cfg.get("subcontractors", [])}
    scans, incs, persons, compliant, ppe_ok = _period(store, now - span, now, subs)
    _, prev_incs, prev_persons, prev_compliant, _ = _period(store, now - 2 * span, now - span, subs)

    real = [i for i in incs if i["status"] != "false_alarm"]
    score = round(100 * compliant / persons, 1) if persons else 100.0
    prev_score = round(100 * prev_compliant / prev_persons, 1) if prev_persons else None
    grade, risk = _grade(score)

    breakdown = Counter()
    zone_of = {}
    for i in real:
        for t in json.loads(i["types"]):
            breakdown[t] += 1
            zone_of.setdefault(t, Counter())[i["zone_name"] or i["camera_name"] or "Upload"] += 1
    total_events = sum(breakdown.values())
    breakdown_list = [{
        "type": t, "title": VIOLATIONS[t]["title"], "category": VIOLATIONS[t]["category"], "count": c,
        "share": round(c / total_events, 3) if total_events else 0,
        "top_location": zone_of[t].most_common(1)[0][0],
    } for t, c in breakdown.most_common() if t in VIOLATIONS]

    leaderboard = []
    for sid, s in subs.items():
        sp = sum(x["persons"] for x in scans if x["subcontractor"] == sid)
        sc = sum(x["compliant"] for x in scans if x["subcontractor"] == sid)
        rate = round(100 * sc / sp, 1) if sp else None
        n_inc = sum(1 for i in real if i["subcontractor"] == s["name"])
        status = "no_data" if rate is None else "top" if rate >= 95 else "satisfactory" if rate >= 85 else "warning"
        leaderboard.append({"id": sid, "name": s["name"], "trade": s.get("trade"), "workers": s.get("workers"),
                            "compliance": rate, "incidents": n_inc, "status": status})
    leaderboard.sort(key=lambda x: -1 if x["compliance"] is None else x["compliance"], reverse=True)

    acks = [i["ack_at"] - i["created_at"] for i in incs if i["ack_at"] and i["status"] == "acknowledged"]
    last_critical = store.query("SELECT MAX(created_at) AS t FROM incidents WHERE severity='critical' "
                                "AND status!='false_alarm'")[0]["t"]
    false_alarms = sum(1 for i in incs if i["status"] == "false_alarm")

    # trend: hourly buckets for today, daily buckets for week / month
    from datetime import datetime
    bucket = 3600 if rng == "today" else 86400
    n_buckets = int(span // bucket)
    start = now - n_buckets * bucket
    trend = []
    for k in range(n_buckets):
        b0, b1 = start + k * bucket, start + (k + 1) * bucket
        label = datetime.fromtimestamp(b1).strftime("%H:00" if bucket == 3600 else "%d.%m")
        trend.append({
            "label": label,
            "violations": sum(1 for i in real if b0 <= i["created_at"] < b1),
            "scanned": sum(x["persons"] for x in scans if b0 <= x["ts"] < b1),
        })
    by_cam = Counter(i["camera_id"] or "UPLOAD" for i in real)
    cam_names = {c["id"]: c["name"] for c in cfg.get("cameras", [])}
    by_camera = [{"camera_id": k, "name": cam_names.get(k, "Field uploads"), "count": v}
                 for k, v in by_cam.most_common()]
    return {
        "range": rng,
        "compliance_index": score,
        "compliance_change": None if prev_score is None else round(score - prev_score, 1),
        "grade": grade,
        "risk": risk,
        "days_since_critical": None if last_critical is None else int((now - last_critical) // 86400),
        "total_scanned": persons,
        "active_violations": sum(1 for i in incs if i["status"] == "open"),
        "violations": len(real),
        "violations_change": len(real) - len([i for i in prev_incs if i["status"] != "false_alarm"]),
        "mttr_seconds": round(sum(acks) / len(acks)) if acks else None,
        "ppe_rate": round(100 * ppe_ok / persons, 1) if persons else None,
        "false_alarm_rate": round(false_alarms / len(incs), 3) if incs else None,
        "breakdown": breakdown_list,
        "total_events": total_events,
        "leaderboard": leaderboard,
        "trend": trend,
        "by_camera": by_camera,
    }
