// Data models mirroring the CVSAFE API responses.

double _d(dynamic v, [double def = 0]) => v == null ? def : (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
int _i(dynamic v, [int def = 0]) => v == null ? def : (v as num).toInt();
List<String> _sl(dynamic v) => v == null ? <String>[] : (v as List).map((e) => e.toString()).toList();

const Map<String, String> violationLabels = {
  'no_hardhat': 'No Hard Hat',
  'no_vest': 'No Safety Vest',
  'no_harness_at_height': 'No Harness Attached',
  'zone_breach': 'Geofence Perimeter Breach',
  'fall': 'Possible Fall',
  'vehicle_proximity': 'Too Close to Machinery',
};

class TimelineEvent {
  final double ts;
  final String kind;
  final String text;
  TimelineEvent(this.ts, this.kind, this.text);

  factory TimelineEvent.fromJson(Map<String, dynamic> j) =>
      TimelineEvent(_d(j['ts']), j['kind'] as String? ?? '', j['text'] as String? ?? '');
}

class Incident {
  final int id;
  final double createdAt;
  final double updatedAt;
  final String? cameraId;
  final String? cameraName;
  final String? zoneName;
  final String? subcontractor;
  final List<String> types;
  final List<String> categories;
  final List<String> references;
  final String title;
  final String severity;
  final double? confidence;
  final List<String> personIds;
  final int count;
  String status;
  double? ackAt;
  final String source;
  final String? imageUrl;
  final String? rawUrl;
  final String? mode;
  List<TimelineEvent> timeline;

  Incident({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.cameraId,
    this.cameraName,
    this.zoneName,
    this.subcontractor,
    required this.types,
    required this.categories,
    required this.references,
    required this.title,
    required this.severity,
    this.confidence,
    required this.personIds,
    required this.count,
    required this.status,
    this.ackAt,
    required this.source,
    this.imageUrl,
    this.rawUrl,
    this.mode,
    required this.timeline,
  });

  bool get isOpen => status == 'open';
  bool get isCritical => severity == 'critical';

  String get categoryLabel {
    if (types.contains('fall')) return 'FALL HAZARD';
    if (types.contains('zone_breach')) return 'CRITICAL BREACH';
    if (types.contains('no_harness_at_height')) return 'WORK AT HEIGHT';
    if (types.contains('vehicle_proximity')) return 'MACHINERY RISK';
    return 'PPE VIOLATION';
  }

  factory Incident.fromJson(Map<String, dynamic> j) {
    final meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return Incident(
      id: _i(j['id']),
      createdAt: _d(j['created_at']),
      updatedAt: _d(j['updated_at'] ?? j['created_at']),
      cameraId: j['camera_id'] as String?,
      cameraName: j['camera_name'] as String?,
      zoneName: j['zone_name'] as String?,
      subcontractor: j['subcontractor'] as String?,
      types: _sl(j['types']),
      categories: _sl(j['categories']),
      references: _sl(j['references']),
      title: j['title'] as String? ?? 'Incident',
      severity: j['severity'] as String? ?? 'moderate',
      confidence: _dn(j['confidence']),
      personIds: _sl(j['person_ids']),
      count: _i(j['count'], 1),
      status: j['status'] as String? ?? 'open',
      ackAt: _dn(j['ack_at']),
      source: j['source'] as String? ?? 'camera',
      imageUrl: j['image_url'] as String?,
      rawUrl: j['raw_url'] as String?,
      mode: meta['mode'] as String?,
      timeline: ((j['timeline'] as List?) ?? const [])
          .map((e) => TimelineEvent.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class Zone {
  final String id;
  String name;
  String type; // restricted | height
  final List<List<double>> polygon; // normalised [x, y] points, 0..1
  Zone(this.id, this.name, this.type, [List<List<double>>? polygon]) : polygon = polygon ?? [];
  factory Zone.fromJson(Map<String, dynamic> j) => Zone(
        j['id'] as String? ?? '',
        j['name'] as String? ?? '',
        j['type'] as String? ?? 'restricted',
        ((j['polygon'] as List?) ?? const [])
            .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
      );
  Map<String, dynamic> toJson() => {'id': id.isEmpty ? null : id, 'name': name, 'type': type, 'polygon': polygon};
}

class Camera {
  final String id;
  final String name;
  final String? subcontractor;
  final String? subcontractorId;
  final String? source; // only returned to admins
  final bool hasReference;
  final bool live;
  final double fps;
  final int persons;
  final int openViolations;
  final List<Zone> zones;
  Camera({
    required this.id,
    required this.name,
    this.subcontractor,
    this.subcontractorId,
    this.source,
    this.hasReference = false,
    required this.live,
    required this.fps,
    required this.persons,
    required this.openViolations,
    required this.zones,
  });
  factory Camera.fromJson(Map<String, dynamic> j) => Camera(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        subcontractor: j['subcontractor'] as String?,
        subcontractorId: j['subcontractor_id'] as String?,
        source: j['source'] as String?,
        hasReference: j['has_reference'] as bool? ?? false,
        live: j['live'] as bool? ?? false,
        fps: _d(j['fps']),
        persons: _i(j['persons']),
        openViolations: _i(j['open_violations']),
        zones: ((j['zones'] as List?) ?? const [])
            .map((e) => Zone.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class Subcontractor {
  final String id;
  final String name;
  final String trade;
  final int workers;
  Subcontractor(this.id, this.name, this.trade, this.workers);
  factory Subcontractor.fromJson(Map<String, dynamic> j) =>
      Subcontractor(j['id'] as String? ?? '', j['name'] as String? ?? '', j['trade'] as String? ?? '', _i(j['workers']));
}

class UserInfo {
  final int id;
  final String username;
  final String name;
  final String role; // admin | ohs | field
  UserInfo(this.id, this.username, this.name, this.role);
  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
      _i(j['id']), j['username'] as String? ?? '', j['name'] as String? ?? '', j['role'] as String? ?? 'field');
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'name': name, 'role': role};
  bool get isAdmin => role == 'admin';
  bool get canManage => role == 'admin' || role == 'ohs';
  String get roleLabel => const {'admin': 'Administrator', 'ohs': 'OHS Specialist', 'field': 'Site Manager'}[role] ?? role;
}

class SiteInfo {
  final String name;
  final String block;
  final List<Camera> cameras;
  final List<Subcontractor> subcontractors;
  final String mode;
  SiteInfo({required this.name, required this.block, required this.cameras, required this.mode, this.subcontractors = const []});
  factory SiteInfo.fromJson(Map<String, dynamic> j) {
    final site = (j['site'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return SiteInfo(
      name: site['name'] as String? ?? 'Site',
      block: site['block'] as String? ?? '',
      mode: j['mode'] as String? ?? 'baseline',
      cameras: ((j['cameras'] as List?) ?? const [])
          .map((e) => Camera.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      subcontractors: ((j['subcontractors'] as List?) ?? const [])
          .map((e) => Subcontractor.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class Health {
  final String mode;
  final int streamsTotal;
  final int streamsActive;
  final double latencyMs;
  final double aggFps;
  Health({required this.mode, required this.streamsTotal, required this.streamsActive, required this.latencyMs, required this.aggFps});
  factory Health.fromJson(Map<String, dynamic> j) => Health(
        mode: j['mode'] as String? ?? 'baseline',
        streamsTotal: _i(j['streams_total']),
        streamsActive: _i(j['streams_active']),
        latencyMs: _d(j['latency_ms']),
        aggFps: _d(j['agg_fps']),
      );
}

class BreakdownItem {
  final String type;
  final String title;
  final int count;
  final double share;
  final String topLocation;
  BreakdownItem(this.type, this.title, this.count, this.share, this.topLocation);
  factory BreakdownItem.fromJson(Map<String, dynamic> j) => BreakdownItem(j['type'] as String? ?? '',
      j['title'] as String? ?? '', _i(j['count']), _d(j['share']), j['top_location'] as String? ?? '');
}

class LeaderRow {
  final String name;
  final String trade;
  final int workers;
  final double? compliance;
  final int incidents;
  final String status;
  LeaderRow(this.name, this.trade, this.workers, this.compliance, this.incidents, this.status);
  factory LeaderRow.fromJson(Map<String, dynamic> j) => LeaderRow(j['name'] as String? ?? '',
      j['trade'] as String? ?? '', _i(j['workers']), _dn(j['compliance']), _i(j['incidents']),
      j['status'] as String? ?? 'no_data');
}

class TrendPoint {
  final String label;
  final int violations;
  final int scanned;
  TrendPoint(this.label, this.violations, this.scanned);
  factory TrendPoint.fromJson(Map<String, dynamic> j) =>
      TrendPoint(j['label'] as String? ?? '', _i(j['violations']), _i(j['scanned']));
}

class CameraCount {
  final String cameraId;
  final String name;
  final int count;
  CameraCount(this.cameraId, this.name, this.count);
  factory CameraCount.fromJson(Map<String, dynamic> j) =>
      CameraCount(j['camera_id'] as String? ?? '', j['name'] as String? ?? '', _i(j['count']));
}

class Analytics {
  final double complianceIndex;
  final double? complianceChange;
  final String grade;
  final String risk;
  final int? daysSinceCritical;
  final int totalScanned;
  final int activeViolations;
  final int violations;
  final int violationsChange;
  final int? mttrSeconds;
  final double? ppeRate;
  final double? falseAlarmRate;
  final List<BreakdownItem> breakdown;
  final int totalEvents;
  final List<LeaderRow> leaderboard;
  final List<TrendPoint> trend;
  final List<CameraCount> byCamera;
  Analytics({
    required this.complianceIndex,
    this.complianceChange,
    required this.grade,
    required this.risk,
    this.daysSinceCritical,
    required this.totalScanned,
    required this.activeViolations,
    required this.violations,
    required this.violationsChange,
    this.mttrSeconds,
    this.ppeRate,
    this.falseAlarmRate,
    required this.breakdown,
    required this.totalEvents,
    required this.leaderboard,
    this.trend = const [],
    this.byCamera = const [],
  });
  factory Analytics.fromJson(Map<String, dynamic> j) => Analytics(
        complianceIndex: _d(j['compliance_index'], 100),
        complianceChange: _dn(j['compliance_change']),
        grade: j['grade'] as String? ?? '-',
        risk: j['risk'] as String? ?? '',
        daysSinceCritical: j['days_since_critical'] == null ? null : _i(j['days_since_critical']),
        totalScanned: _i(j['total_scanned']),
        activeViolations: _i(j['active_violations']),
        violations: _i(j['violations']),
        violationsChange: _i(j['violations_change']),
        mttrSeconds: j['mttr_seconds'] == null ? null : _i(j['mttr_seconds']),
        ppeRate: _dn(j['ppe_rate']),
        falseAlarmRate: _dn(j['false_alarm_rate']),
        breakdown: ((j['breakdown'] as List?) ?? const [])
            .map((e) => BreakdownItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        totalEvents: _i(j['total_events']),
        leaderboard: ((j['leaderboard'] as List?) ?? const [])
            .map((e) => LeaderRow.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        trend: ((j['trend'] as List?) ?? const [])
            .map((e) => TrendPoint.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        byCamera: ((j['by_camera'] as List?) ?? const [])
            .map((e) => CameraCount.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class PpeState {
  final bool? state;
  final double conf;
  PpeState(this.state, this.conf);
  factory PpeState.fromJson(dynamic j) {
    if (j is! Map) return PpeState(null, 0);
    return PpeState(j['state'] as bool?, _d(j['conf']));
  }
}

class PersonResult {
  final int id;
  final double conf;
  final Map<String, PpeState> ppe;
  final List<String> zones;
  final List<String> violations;
  PersonResult(this.id, this.conf, this.ppe, this.zones, this.violations);
  factory PersonResult.fromJson(Map<String, dynamic> j) {
    final raw = (j['ppe'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return PersonResult(
      _i(j['id']),
      _d(j['conf']),
      raw.map((k, v) => MapEntry(k, PpeState.fromJson(v))),
      _sl(j['zones']),
      _sl(j['violations']),
    );
  }
}

class ViolationCount {
  final String type;
  final String title;
  final String severity;
  final int count;
  ViolationCount(this.type, this.title, this.severity, this.count);
  factory ViolationCount.fromJson(Map<String, dynamic> j) => ViolationCount(j['type'] as String? ?? '',
      j['title'] as String? ?? '', j['severity'] as String? ?? 'moderate', _i(j['count']));
}

List<ViolationCount> _violations(dynamic summary) {
  final s = (summary as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  return ((s['violations'] as List?) ?? const [])
      .map((e) => ViolationCount.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}

class ImageScanResult {
  final String mode;
  final double latencyMs;
  final String imageUrl;
  final String rawUrl;
  final List<PersonResult> persons;
  final List<String> vehicles;
  final int compliant;
  final List<ViolationCount> violations;
  final List<int> incidentIds;
  ImageScanResult({
    required this.mode,
    required this.latencyMs,
    required this.imageUrl,
    required this.rawUrl,
    required this.persons,
    required this.vehicles,
    required this.compliant,
    required this.violations,
    required this.incidentIds,
  });
  factory ImageScanResult.fromJson(Map<String, dynamic> j) {
    final summary = (j['summary'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return ImageScanResult(
      mode: j['mode'] as String? ?? 'baseline',
      latencyMs: _d(j['latency_ms']),
      imageUrl: j['image_url'] as String? ?? '',
      rawUrl: j['raw_url'] as String? ?? '',
      persons: ((j['persons'] as List?) ?? const [])
          .map((e) => PersonResult.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      vehicles: ((j['vehicles'] as List?) ?? const []).map((e) => ((e as Map)['label'] ?? '').toString()).toList(),
      compliant: _i(summary['compliant']),
      violations: _violations(summary),
      incidentIds: ((j['incident_ids'] as List?) ?? const []).map((e) => _i(e)).toList(),
    );
  }
}

class VideoIncident {
  final int? incidentId;
  final int trackId;
  final double tOffset;
  final String title;
  final String severity;
  final List<String> types;
  final String imageUrl;
  VideoIncident(this.incidentId, this.trackId, this.tOffset, this.title, this.severity, this.types, this.imageUrl);
  factory VideoIncident.fromJson(Map<String, dynamic> j) => VideoIncident(
        j['incident_id'] == null ? null : _i(j['incident_id']),
        _i(j['track_id']),
        _d(j['t_offset']),
        j['title'] as String? ?? '',
        j['severity'] as String? ?? 'moderate',
        _sl(j['types']),
        j['image_url'] as String? ?? '',
      );
}

class VideoScanResult {
  final String mode;
  final double durationS;
  final double analyzedS;
  final int framesAnalyzed;
  final double sampleFps;
  final double latencyMs;
  final int personsTracked;
  final int personsCompliant;
  final double? frameCompliance;
  final List<ViolationCount> violations;
  final List<VideoIncident> incidents;
  VideoScanResult({
    required this.mode,
    required this.durationS,
    required this.analyzedS,
    required this.framesAnalyzed,
    required this.sampleFps,
    required this.latencyMs,
    required this.personsTracked,
    required this.personsCompliant,
    this.frameCompliance,
    required this.violations,
    required this.incidents,
  });
  factory VideoScanResult.fromJson(Map<String, dynamic> j) => VideoScanResult(
        mode: j['mode'] as String? ?? 'baseline',
        durationS: _d(j['duration_s']),
        analyzedS: _d(j['analyzed_s']),
        framesAnalyzed: _i(j['frames_analyzed']),
        sampleFps: _d(j['sample_fps']),
        latencyMs: _d(j['latency_ms']),
        personsTracked: _i(j['persons_tracked']),
        personsCompliant: _i(j['persons_compliant']),
        frameCompliance: _dn(j['frame_compliance']),
        violations: _violations(j['summary']),
        incidents: ((j['incidents'] as List?) ?? const [])
            .map((e) => VideoIncident.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class VideoJob {
  final String id;
  final String status; // queued | running | done | error
  final double progress;
  final VideoScanResult? result;
  final String? error;
  VideoJob(this.id, this.status, this.progress, this.result, this.error);
  factory VideoJob.fromJson(Map<String, dynamic> j) => VideoJob(
        j['id'] as String? ?? '',
        j['status'] as String? ?? 'queued',
        _d(j['progress']),
        j['result'] == null ? null : VideoScanResult.fromJson((j['result'] as Map).cast<String, dynamic>()),
        j['error'] as String?,
      );
}
