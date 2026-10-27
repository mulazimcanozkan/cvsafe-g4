"""PDF safety report (the full multi-page dossier is a web-portal feature;
this is the summary the mobile app can download)."""
import io
import os
import time
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

FONT, BOLD = "Helvetica", "Helvetica-Bold"
for reg, bold in (("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                   "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
                  ("C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/arialbd.ttf"),
                  ("/Library/Fonts/Arial Unicode.ttf", "/Library/Fonts/Arial Unicode.ttf")):
    if os.path.isfile(reg) and os.path.isfile(bold):
        pdfmetrics.registerFont(TTFont("RptFont", reg))
        pdfmetrics.registerFont(TTFont("RptFontBold", bold))
        FONT, BOLD = "RptFont", "RptFontBold"
        break


def _fmt_time(ts):
    return datetime.fromtimestamp(ts).strftime("%d.%m.%Y %H:%M")


def build_pdf(stats, incidents, cfg, media_dir):
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm,
                            topMargin=1.6 * cm, bottomMargin=1.6 * cm, title="CVSAFE Safety Report")
    h1 = ParagraphStyle("h1", fontName=BOLD, fontSize=16, leading=20, spaceAfter=4)
    h2 = ParagraphStyle("h2", fontName=BOLD, fontSize=12, leading=16, spaceBefore=12, spaceAfter=6)
    body = ParagraphStyle("b", fontName=FONT, fontSize=9.5, leading=13)
    small = ParagraphStyle("s", fontName=FONT, fontSize=8, leading=10, textColor=colors.grey)
    site = cfg.get("site", {})
    s = [Paragraph("CVSAFE - Site Safety Report", h1),
         Paragraph(f"{site.get('name', '')} {site.get('block', '')} | Period: {stats['range']} | "
                   f"Generated {_fmt_time(time.time())}", small), Spacer(1, 8)]

    def table(rows, widths, header=True):
        t = Table(rows, colWidths=widths, repeatRows=1 if header else 0)
        style = [("FONT", (0, 0), (-1, -1), FONT, 9), ("GRID", (0, 0), (-1, -1), 0.4, colors.grey),
                 ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("TOPPADDING", (0, 0), (-1, -1), 3),
                 ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
        if header:
            style += [("FONT", (0, 0), (-1, 0), BOLD, 9), ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EEEEEE"))]
        t.setStyle(TableStyle(style))
        return t

    mttr = stats["mttr_seconds"]
    kpis = [["Compliance index", f"{stats['compliance_index']} / 100 (Grade {stats['grade']}, {stats['risk']})"],
            ["People scanned by AI", str(stats["total_scanned"])],
            ["Violations (excl. false alarms)", str(stats["violations"])],
            ["Open violations", str(stats["active_violations"])],
            ["PPE compliance rate", "-" if stats["ppe_rate"] is None else f"{stats['ppe_rate']}%"],
            ["Mean time to respond", "-" if mttr is None else f"{mttr // 60}m {mttr % 60}s"],
            ["False alarm rate", "-" if stats["false_alarm_rate"] is None else f"{stats['false_alarm_rate']:.0%}"]]
    s += [Paragraph("Summary", h2), table(kpis, [6 * cm, 11 * cm], header=False)]

    if stats["breakdown"]:
        rows = [["Violation", "Count", "Share", "Most frequent location"]]
        rows += [[b["title"], b["count"], f"{b['share']:.0%}", b["top_location"]] for b in stats["breakdown"]]
        s += [Paragraph("Violation breakdown", h2), table(rows, [6 * cm, 2 * cm, 2 * cm, 7 * cm])]

    rows = [["Subcontractor", "Trade", "Compliance", "Incidents"]]
    rows += [[l["name"], l["trade"] or "", "-" if l["compliance"] is None else f"{l['compliance']}%", l["incidents"]]
             for l in stats["leaderboard"]]
    s += [Paragraph("Subcontractors", h2), table(rows, [5.5 * cm, 5 * cm, 3 * cm, 3.5 * cm])]

    s += [Paragraph("Incident log", h2)]
    rows = [["#", "Time", "Incident", "Location", "Status", "Evidence"]]
    for i in incidents[:40]:
        img = ""
        if i.get("image"):
            p = os.path.join(media_dir, i["image"])
            if os.path.isfile(p):
                img = Image(p, width=2.6 * cm, height=1.8 * cm, kind="proportional")
        rows.append([str(i["id"]), Paragraph(_fmt_time(i["created_at"]), body), Paragraph(i["title"], body),
                     Paragraph(f"{i.get('camera_id') or 'Upload'} {i.get('zone_name') or ''}", body),
                     i["status"].replace("_", " "), img])
    s += [table(rows, [1.1 * cm, 2.2 * cm, 4.9 * cm, 3.5 * cm, 2.3 * cm, 3.4 * cm])]
    s += [Spacer(1, 10), Paragraph(
        "Faces are blurred in all stored evidence (KVKK). Regulation references are guidance for the OHS "
        "specialist and must be confirmed for each case.", small)]
    doc.build(s)
    return buf.getvalue()
