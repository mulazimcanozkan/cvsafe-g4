import 'models.dart';

/// Offline sample data so the app can be shown without a running server.
/// AI scanning is disabled in this mode.
class DemoData {
  static double _ago(int minutes) => DateTime.now().millisecondsSinceEpoch / 1000 - minutes * 60;

  static List<Incident> incidents() {
    Incident mk(int id, int mins, String cam, String camName, String? zone, String sub, List<String> types,
        String title, String sev, double conf, List<String> cats, List<String> refs, {int count = 1}) {
      final t = _ago(mins);
      return Incident(
        id: id,
        createdAt: t,
        updatedAt: t,
        cameraId: cam,
        cameraName: camName,
        zoneName: zone,
        subcontractor: sub,
        types: types,
        categories: cats,
        references: refs,
        title: title,
        severity: sev,
        confidence: conf,
        personIds: ['${200 + id}'],
        count: count,
        status: 'open',
        source: 'demo',
        timeline: [
          TimelineEvent(t, 'ai', '$title flagged at $cam${zone == null ? '' : ' / $zone'}.'),
          TimelineEvent(t + 3, 'telemetry', 'Push alert dispatched to field manager.'),
        ],
      );
    }

    return [
      mk(8841, 1, 'CAM-03', 'Tower Crane Radius', 'Crane 2 Hook Radius', 'Demir Beton A.S.',
          ['no_vest', 'zone_breach'], 'Danger Zone Breach & Missing High-Vis Vest', 'critical', 0.94, ['ppe', 'zone'],
          ['Yapi Isleri ISG Yonetmeligi Ek-4 / 6331 s. Kanun Md. 4']),
      mk(8839, 3, 'CAM-02', 'South Facade Scaffolding', 'Scaffold Level 4', 'Ozkan Iskele Yapi San.',
          ['no_harness_at_height'], 'Missing Safety Harness at Height', 'critical', 0.96, ['height'],
          ['Yapi Isleri ISG Yonetmeligi Ek-4 (yuksekte calisma)']),
      mk(8835, 8, 'CAM-01', 'Excavation Pit East', 'Deep Trench Perimeter', 'Kaya Harfiyat',
          ['no_hardhat', 'no_vest'], 'Missing PPE: High-Vis Vest & Hard Hat', 'moderate', 0.91, ['ppe'],
          ['KKD Yonetmeligi (2013) / 6331 s. Kanun Md. 4'],
          count: 2),
    ];
  }

  static SiteInfo site() => SiteInfo(name: 'Yildiz Tower', block: 'Zone B', mode: 'demo', cameras: [
        Camera(id: 'CAM-01', name: 'Excavation Pit East', subcontractor: 'Kaya Harfiyat', live: false, fps: 0, persons: 6,
            openViolations: 1, zones: [Zone('pit-edge', 'Deep Trench Perimeter', 'restricted')]),
        Camera(id: 'CAM-02', name: 'South Facade Scaffolding', subcontractor: 'Ozkan Iskele Yapi San.', live: false,
            fps: 0, persons: 4, openViolations: 1, zones: [Zone('scaffold-l4', 'Scaffold Level 4', 'height')]),
        Camera(id: 'CAM-03', name: 'Tower Crane Radius', subcontractor: 'Demir Beton A.S.', live: false, fps: 0,
            persons: 3, openViolations: 1, zones: [Zone('crane-2', 'Crane 2 Hook Radius', 'restricted')]),
        Camera(id: 'CAM-04', name: 'South Perimeter / Crane Hoist', subcontractor: 'Anka Celik Yapi', live: false,
            fps: 0, persons: 0, openViolations: 0, zones: []),
      ]);

  static Analytics analytics() => Analytics(
        complianceIndex: 92,
        complianceChange: 4.2,
        grade: 'A',
        risk: 'Low Risk',
        daysSinceCritical: 0,
        totalScanned: 14820,
        activeViolations: 3,
        violations: 11,
        violationsChange: -3,
        mttrSeconds: 192,
        ppeRate: 96.4,
        falseAlarmRate: 0.08,
        totalEvents: 11,
        breakdown: [
          BreakdownItem('no_vest', 'Missing High-Vis Vest', 5, 0.42, 'Scaffold Level 4'),
          BreakdownItem('zone_breach', 'Danger Zone Breach', 3, 0.28, 'Crane 2 Hook Radius'),
          BreakdownItem('no_hardhat', 'Missing Hard Hat', 2, 0.18, 'Excavation Pit East'),
          BreakdownItem('no_harness_at_height', 'Missing Safety Harness at Height', 1, 0.12, 'Scaffold Level 4'),
        ],
        leaderboard: [
          LeaderRow('Anka Celik Yapi', 'Steel Erection', 52, 98, 0, 'top'),
          LeaderRow('Demir Beton A.S.', 'Formwork & Casting', 34, 91, 1, 'satisfactory'),
          LeaderRow('Ozkan Iskele Yapi San.', 'Scaffolding', 22, 88, 1, 'satisfactory'),
          LeaderRow('Kaya Harfiyat', 'Heavy Excavation', 18, 79, 1, 'warning'),
        ],
      );
}
