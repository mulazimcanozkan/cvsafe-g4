import 'package:cvsafe_mobile/demo.dart';
import 'package:cvsafe_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an incident from the API', () {
    final inc = Incident.fromJson({
      'id': 12,
      'created_at': 1700000000.0,
      'updated_at': 1700000005.0,
      'camera_id': 'CAM-03',
      'camera_name': 'Tower Crane Radius',
      'zone_name': 'Crane 2 Hook Radius',
      'subcontractor': 'Demir Beton A.S.',
      'types': ['no_vest', 'zone_breach'],
      'categories': ['ppe', 'zone'],
      'references': ['Ek-4'],
      'title': 'Danger Zone Breach & Missing High-Vis Vest',
      'severity': 'critical',
      'confidence': 0.94,
      'person_ids': [212],
      'count': 2,
      'status': 'open',
      'ack_at': null,
      'source': 'camera',
      'image_url': '/media/cam_1.jpg',
      'raw_url': '/media/raw_1.jpg',
      'meta': {'mode': 'baseline'},
      'timeline': [
        {'ts': 1700000000.0, 'kind': 'ai', 'text': 'flagged'}
      ],
    });
    expect(inc.isCritical, isTrue);
    expect(inc.categoryLabel, 'CRITICAL BREACH');
    expect(inc.personIds, ['212']);
    expect(inc.timeline.single.kind, 'ai');
  });

  test('parses an image scan result', () {
    final r = ImageScanResult.fromJson({
      'mode': 'baseline',
      'latency_ms': 210.5,
      'image_url': '/media/a.jpg',
      'raw_url': '/media/b.jpg',
      'persons': [
        {
          'id': 1,
          'conf': 0.9,
          'ppe': {
            'hardhat': {'state': false, 'conf': 0.8},
            'vest': {'state': true, 'conf': 0.7},
            'harness': {'state': null, 'conf': 0.0}
          },
          'zones': [],
          'violations': ['no_hardhat']
        }
      ],
      'vehicles': [
        {'label': 'truck', 'conf': 0.8}
      ],
      'summary': {
        'persons': 1,
        'compliant': 0,
        'violations': [
          {'type': 'no_hardhat', 'title': 'Missing Hard Hat', 'severity': 'moderate', 'count': 1}
        ]
      },
      'incident_ids': [5],
    });
    expect(r.persons.single.ppe['hardhat']!.state, isFalse);
    expect(r.persons.single.ppe['harness']!.state, isNull);
    expect(r.vehicles, ['truck']);
    expect(r.incidentIds, [5]);
  });

  test('demo data is consistent', () {
    expect(DemoData.incidents(), isNotEmpty);
    expect(DemoData.site().cameras.length, 4);
    expect(DemoData.analytics().leaderboard, isNotEmpty);
  });
}
