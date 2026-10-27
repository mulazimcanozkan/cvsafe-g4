"""Optional demo history so the dashboard is not empty on first run
(start the server with CVSAFE_DEMO=1). Seeded incidents have no images;
real evidence appears as soon as photos/videos are analysed or a camera runs."""
import random
import time

DEMO = [
    ("CAM-03", "Crane 2 Hook Radius", ["zone_breach", "no_vest"], 0.94),
    ("CAM-02", "Scaffold Level 4", ["no_harness_at_height"], 0.96),
    ("CAM-01", "Deep Trench Perimeter", ["no_vest", "no_hardhat"], 0.91),
    ("CAM-04", None, ["no_vest"], 0.88),
    ("CAM-01", None, ["vehicle_proximity"], 0.83),
    ("CAM-02", None, ["no_hardhat"], 0.86),
]


def seed(svc, days=7):
    if svc.store.query("SELECT COUNT(*) AS n FROM incidents")[0]["n"]:
        return
    rnd = random.Random(6331)
    now = time.time()
    for d in range(days, -1, -1):
        for _ in range(12):
            cam = rnd.choice(list(svc.cameras.values()))
            persons = rnd.randint(3, 9)
            bad = rnd.choices([0, 0, 0, 1, 1, 2], k=1)[0]
            svc.store.add_scan(persons=persons, compliant=persons - bad, ppe_ok=persons - max(0, bad - 1),
                               camera_id=cam["id"], subcontractor=cam.get("subcontractor"), source="demo",
                               ts=now - d * 86400 - rnd.randint(0, 80000))
        for _ in range(rnd.randint(1, 3) if d else 0):
            cam_id, zone, types, conf = rnd.choice(DEMO)
            cam = svc.cameras[cam_id]
            ts = now - d * 86400 - rnd.randint(3600, 80000)
            iid = svc.store.add_incident(types=types, camera=cam, zone_name=zone, subcontractor=svc.sub_name(cam),
                                         confidence=conf, person_ids=[rnd.randint(200, 499)], source="demo", ts=ts)
            if rnd.random() < 0.85:
                svc.store.set_status(iid, "acknowledged" if rnd.random() < 0.85 else "false_alarm")
                ack = ts + rnd.randint(60, 400)
                svc.store.db.execute("UPDATE incidents SET ack_at=? WHERE id=?", (ack, iid))
                svc.store.db.execute("UPDATE events SET ts=? WHERE incident_id=? AND kind='user'", (ack, iid))
                svc.store.db.commit()
    # today's open alerts, newest last
    for mins, (cam_id, zone, types, conf) in zip((8, 3, 1), DEMO[2::-1]):
        cam = svc.cameras[cam_id]
        svc.store.add_incident(types=types, camera=cam, zone_name=zone, subcontractor=svc.sub_name(cam),
                               confidence=conf, person_ids=[rnd.randint(200, 499)], source="demo",
                               ts=now - mins * 60)
