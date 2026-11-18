import 'dart:convert';

import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:cvsafe_web_panel/main.dart';
import 'package:cvsafe_web_panel/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    debugDisableGoogleFonts = true;
    SharedPreferences.setMockInitialValues({});
  });

  http.Response jsonResp(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, dynamic> sampleSite() => {
        'site': {'name': 'Maslak Tower', 'block': 'Block B'},
        'mode': 'baseline',
        'cameras': [
          {
            'id': 'CAM-01',
            'name': 'Excavation Pit East',
            'subcontractor': 'Kaya Insaat',
            'subcontractor_id': 'kaya',
            'source': 'rtsp://admin:secret@192.168.1.21/stream1',
            'live': true,
            'fps': 2.0,
            'persons': 4,
            'open_violations': 1,
            'has_reference': true,
            'zones': [
              {
                'id': 'pit-edge',
                'name': 'Pit Edge',
                'type': 'restricted',
                'polygon': [
                  [0.1, 0.1],
                  [0.6, 0.1],
                  [0.6, 0.6],
                ]
              }
            ]
          }
        ],
        'subcontractors': [
          {'id': 'kaya', 'name': 'Kaya Insaat', 'trade': 'Excavation', 'workers': 18}
        ]
      };

  List<Map<String, dynamic>> sampleIncidents() => [
        {
          'id': 101,
          'created_at': 1700000000.0,
          'updated_at': 1700000005.0,
          'camera_id': 'CAM-01',
          'camera_name': 'Excavation Pit East',
          'zone_name': 'Pit Edge',
          'subcontractor': 'Kaya Insaat',
          'types': ['zone_breach', 'no_vest'],
          'categories': ['zone', 'ppe'],
          'references': ['6331 s. Kanun Md. 4'],
          'title': 'Danger Zone Breach & Missing High-Vis Vest',
          'severity': 'critical',
          'confidence': 0.93,
          'person_ids': [12],
          'count': 2,
          'status': 'open',
          'ack_at': null,
          'source': 'camera',
          'image_url': null,
          'raw_url': null,
          'meta': {'mode': 'baseline'},
          'timeline': [
            {'ts': 1700000000.0, 'kind': 'ai', 'text': 'Flagged at CAM-01 / Pit Edge.'}
          ],
        }
      ];

  Map<String, dynamic> sampleAnalytics() => {
        'compliance_index': 92.0,
        'grade': 'A',
        'risk': 'Low Risk',
        'total_scanned': 120,
        'active_violations': 1,
        'violations': 3,
        'violations_change': -1,
        'mttr_seconds': 85,
        'ppe_rate': 94.5,
        'false_alarm_rate': 0.1,
        'breakdown': [
          {
            'type': 'no_vest',
            'title': 'Missing High-Vis Vest',
            'count': 2,
            'share': 0.67,
            'top_location': 'Pit Edge',
          }
        ],
        'total_events': 3,
        'leaderboard': [
          {
            'name': 'Kaya Insaat',
            'trade': 'Excavation',
            'workers': 18,
            'compliance': 92.0,
            'incidents': 2,
            'status': 'satisfactory',
          }
        ],
        'trend': [
          {'label': '08:00', 'violations': 1, 'scanned': 20},
          {'label': '09:00', 'violations': 2, 'scanned': 25},
        ],
        'by_camera': [
          {'camera_id': 'CAM-01', 'name': 'Excavation Pit East', 'count': 3}
        ]
      };

  ApiClientFactory buildMockApi({
    String role = 'admin',
    List<http.Request>? log,
  }) {
    final incidents = sampleIncidents();
    final users = <Map<String, dynamic>>[
      {
        'id': 1,
        'username': 'admin',
        'name': 'Site Administrator',
        'role': role,
        'is_active': true,
        'last_login_at': 1700000100.0,
      },
      {
        'id': 2,
        'username': 'isg',
        'name': 'OHS Specialist',
        'role': 'ohs',
        'is_active': true,
        'last_login_at': null,
      },
    ];

    return (baseUrl, {token, onUnauthorized}) {
      return ApiClient(
        baseUrl,
        token: token,
        onUnauthorized: onUnauthorized,
        httpClient: MockClient((req) async {
          log?.add(req);
          final p = req.url.path;
          if (p == '/health') {
            return jsonResp({
              'status': 'ok',
              'mode': 'baseline',
              'streams_total': 4,
              'streams_active': 2,
              'latency_ms': 42.0,
              'agg_fps': 4.0,
            });
          }
          if (p == '/auth/login' && req.method == 'POST') {
            return jsonResp({'token': 'test-token', 'user': users.first});
          }
          if (p == '/auth/me') {
            return jsonResp(users.first);
          }
          if (p == '/auth/logout') {
            return jsonResp({'ok': true});
          }
          if (p == '/site') {
            return jsonResp(sampleSite());
          }
          if (p == '/false_alarm_reasons') {
            return jsonResp([
              {'code': 'wrong_detection', 'label': 'Wrong detection'},
              {'code': 'authorised_person', 'label': 'Authorised person in the zone'},
              {'code': 'reflection_shadow', 'label': 'Reflection or shadow'},
              {'code': 'other', 'label': 'Other'},
            ]);
          }
          if (p == '/incidents') {
            return jsonResp(incidents);
          }
          if (p == '/incidents/101' && req.method == 'GET') {
            return jsonResp(incidents.first);
          }
          if (p == '/incidents/101/false_alarm' && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            incidents.first['status'] = 'false_alarm';
            incidents.first['false_alarm_reason'] = body['reason'];
            (incidents.first['timeline'] as List).add({
              'ts': 1700000050.0,
              'kind': 'user',
              'text': 'Marked as false alarm. Reason: ${body['reason']}. Note: ${body['note'] ?? ''}',
            });
            return jsonResp(incidents.first);
          }
          if (p == '/analytics') {
            return jsonResp(sampleAnalytics());
          }
          if (p == '/users' && req.method == 'GET') {
            return jsonResp(users);
          }
          if (p == '/users/2' && req.method == 'PATCH') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body.containsKey('name')) users[1]['name'] = body['name'];
            if (body.containsKey('role')) users[1]['role'] = body['role'];
            if (body.containsKey('is_active')) users[1]['is_active'] = body['is_active'];
            return jsonResp(users[1]);
          }
          if (p == '/cameras/CAM-01/zones' && req.method == 'PUT') {
            final list = jsonDecode(req.body) as List;
            return jsonResp(list);
          }
          return jsonResp({'detail': 'Not found: $p'}, 404);
        }),
      );
    };
  }

  testWidgets('unauthenticated user sees LoginPage, signs in and lands on DashboardPage', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollEnabledProvider.overrideWithValue(false),
          apiClientFactoryProvider.overrideWithValue(buildMockApi()),
        ],
        child: const CvsafeWebPanelApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'admin');
    await tester.enterText(find.byType(TextField).at(2), 'cvsafe123');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('COMPLIANCE INDEX'), findsOneWidget);
    expect(find.text('92 / 100'), findsOneWidget);
    expect(find.text('Maslak Tower Block B · live overview'), findsOneWidget);
  });

  testWidgets('IncidentsPage opens detail dialog and submits false alarm with reason code', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({
      'session_token': 'test-token',
      'session_user': jsonEncode({'id': 1, 'username': 'admin', 'name': 'Site Administrator', 'role': 'admin'}),
    });

    final requests = <http.Request>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollEnabledProvider.overrideWithValue(false),
          apiClientFactoryProvider.overrideWithValue(buildMockApi(log: requests)),
        ],
        child: const CvsafeWebPanelApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Incidents
    await tester.tap(find.text('Incidents'));
    await tester.pumpAndSettle();

    expect(find.text('Danger Zone Breach & Missing High-Vis Vest'), findsOneWidget);

    // Open the incident detail dialog
    await tester.tap(find.text('Danger Zone Breach & Missing High-Vis Vest'));
    await tester.pumpAndSettle();

    expect(find.text('Mark Addressed'), findsOneWidget);
    expect(find.text('False Alarm'), findsOneWidget);

    // Click False Alarm -> opens reason picker dialog
    await tester.tap(find.text('False Alarm'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as false alarm'), findsOneWidget);
    await tester.tap(find.text('Reflection or shadow'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Optional note'), 'Sun glare on vest');
    await tester.tap(find.text('Confirm False Alarm'));
    await tester.pumpAndSettle();

    final faReq = requests.firstWhere((r) => r.url.path == '/incidents/101/false_alarm');
    expect(jsonDecode(faReq.body), {'reason': 'reflection_shadow', 'note': 'Sun glare on vest'});
    expect(find.text('Reflection or shadow'), findsOneWidget);
  });

  testWidgets('UsersPage allows admin to deactivate a user and blocks OHS role via route guard', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({
      'session_token': 'test-token',
      'session_user': jsonEncode({'id': 1, 'username': 'admin', 'name': 'Site Administrator', 'role': 'admin'}),
    });

    final requests = <http.Request>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollEnabledProvider.overrideWithValue(false),
          apiClientFactoryProvider.overrideWithValue(buildMockApi(log: requests)),
        ],
        child: const CvsafeWebPanelApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(find.text('OHS Specialist'), findsWidgets);
    expect(find.text('ACTIVE'), findsNWidgets(2));

    // Deactivate the second user (isg)
    final deactivateBtn = find.byTooltip('Deactivate');
    await tester.ensureVisible(deactivateBtn);
    await tester.tap(deactivateBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Deactivate'));
    await tester.pumpAndSettle();

    final patchReq = requests.firstWhere((r) => r.url.path == '/users/2' && r.method == 'PATCH');
    expect(jsonDecode(patchReq.body), {'is_active': false});
    expect(find.text('DEACTIVATED'), findsOneWidget);
  });

  testWidgets('ZoneEditorPage renders existing zones and saves drawn zones', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({
      'session_token': 'test-token',
      'session_user': jsonEncode({'id': 1, 'username': 'admin', 'name': 'Site Administrator', 'role': 'admin'}),
    });

    final requests = <http.Request>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pollEnabledProvider.overrideWithValue(false),
          apiClientFactoryProvider.overrideWithValue(buildMockApi(log: requests)),
        ],
        child: const CvsafeWebPanelApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cameras & Zones'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zones'));
    await tester.pumpAndSettle();

    expect(find.text('Zones · CAM-01'), findsOneWidget);
    expect(find.text('Pit Edge'), findsOneWidget);
  });
}
