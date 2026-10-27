"""Violation catalogue: titles, severity and the regulation each one refers to.

The references are pointers for the OHS specialist, not legal advice; the
specialist should confirm the exact article for each site.
"""

VIOLATIONS = {
    "no_hardhat": {
        "title": "Missing Hard Hat",
        "severity": "moderate",
        "category": "ppe",
        "reference": "KKD Yonetmeligi (2013) / 6331 s. Kanun Md. 4",
    },
    "no_vest": {
        "title": "Missing High-Vis Vest",
        "severity": "moderate",
        "category": "ppe",
        "reference": "KKD Yonetmeligi (2013) / 6331 s. Kanun Md. 4",
    },
    "no_harness_at_height": {
        "title": "Missing Safety Harness at Height",
        "severity": "critical",
        "category": "height",
        "reference": "Yapi Isleri ISG Yonetmeligi Ek-4 (yuksekte calisma)",
    },
    "zone_breach": {
        "title": "Danger Zone Breach",
        "severity": "critical",
        "category": "zone",
        "reference": "Yapi Isleri ISG Yonetmeligi Ek-4 / 6331 s. Kanun Md. 4",
    },
    "fall": {
        "title": "Possible Fall Detected",
        "severity": "critical",
        "category": "fall",
        "reference": "6331 s. Kanun Md. 11 (acil durum)",
    },
    "vehicle_proximity": {
        "title": "Worker Too Close to Machinery",
        "severity": "high",
        "category": "proximity",
        "reference": "Yapi Isleri ISG Yonetmeligi Ek-4 (is makineleri)",
    },
}

SEVERITY_RANK = {"critical": 3, "high": 2, "moderate": 1, "low": 0}


def incident_title(types):
    """Combine several violation types of one person into one headline."""
    types = sorted(set(types), key=lambda t: -SEVERITY_RANK[VIOLATIONS[t]["severity"]])
    names = [VIOLATIONS[t]["title"] for t in types]
    if len(names) == 1:
        return names[0]
    if all(VIOLATIONS[t]["category"] == "ppe" for t in types):
        return "Missing PPE: " + " & ".join(n.replace("Missing ", "") for n in names)
    return " & ".join(names)


def incident_severity(types):
    return max((VIOLATIONS[t]["severity"] for t in types), key=lambda s: SEVERITY_RANK[s])
